require "saltbox/actions"
require "saltbox/actions/testing/configuration"
require "saltbox/actions/testing/callers"
require "json_schemer"

module Saltbox
  module Actions
    # Include in ActiveSupport::TestCase and name the action under test once
    # with `tests Events::UpdateAction`, or pass action: to #run_action. No
    # RSpec dependency is loaded.
    module TestHelper
      include Testing::Callers

      class << self
        def config = @config ||= Testing::Configuration.new

        def configure = yield(config)

        def included(base)
          base.class_attribute :action_class, instance_writer: false
          base.extend(ClassMethods)
        end
      end

      module ClassMethods
        # Names the action the test class tests, as ActionMailer::TestCase's
        # `tests` names its mailer. action_class reads it.
        #
        # @param action [Class, String] the action, or its name
        # @return [Class, String]
        def tests(action) = self.action_class = action
      end

      # Runs the action as the caller, through Invocation, the path every
      # surface takes.
      #
      # @param arguments [Hash] the input, as a client would send it
      # @param as [Caller]
      # @param action [Class, String] the action, or its name; the one the class `tests` by default
      # @return [Result]
      # @raise [Error] when the action refuses
      def run_action(arguments = {}, as:, action: action_class)
        raise ArgumentError, "pass action:, or name the action with `tests Events::UpdateAction`" unless action
        Invocation.call(action:, caller: as, arguments:)
      end

      # Returns the refusal so its message and details can also be checked.
      def assert_refused(code = nil, &block)
        error = assert_raises(Error, &block)
        assert_equal code.to_s, error.code if code
        error
      end

      def assert_field_errors(*fields, &block)
        error = assert_refused(&block)
        refute_empty error.errors || {}, "expected field errors, got #{error.code}"
        fields.each { |field| assert_includes error.errors.keys, field.to_s }
        error
      end

      # Without `as:` it checks the catalog's schema, built for
      # Configuration#schema_user; pass a caller when the policy needs a person.
      def assert_invalid_against_schema(arguments, action: action_class, as: nil)
        assert_raises(Error::ValidationFailed) { Arguments.check(action, arguments, as) }
      end

      def assert_matches_output_schema(result, schema: action_class.output_schema)
        raise ArgumentError, "the action declares no output schema: add output_schema" unless schema
        body = result.respond_to?(:body) ? result.body : result
        failures = JSONSchemer.schema(schema).validate(body.as_json).map { it["error"] }
        assert_empty failures, "expected the body to match the output schema:\n#{failures.join("\n")}"
      end

      def assert_runnable_for(caller, action: action_class)
        assert Actions.within(caller) { |fresh| action.runnable_for?(fresh) }, "expected #{action.action_name} to be runnable for #{caller.surface}"
      end

      def assert_listed_for(caller, action: action_class)
        assert Actions.within(caller) { |fresh| action.listed_for?(fresh) }, "expected #{action.action_name} to be listed for #{caller.surface}"
      end

      def assert_announces_changes(expected = {})
        announced = []
        subscriber = ->(*, payload) { announced.concat(payload[:changes]) }
        ActiveSupport::Notifications.subscribed(subscriber, "changes.saltbox_actions") { yield }
        flunk ChangeTracking::NOT_IN_USE if announced.empty? && !ChangeTracking.in_use?
        refute_empty announced if expected.empty?
        expected.each do |target, event|
          type, id = target.is_a?(Class) ? [target.name, nil] : [target.class.name, target.id.to_s]
          assert announced.any? { |t, i, e| t == type && (id.nil? || i.to_s == id) && e.to_s == event.to_s },
            "expected #{target.inspect} => #{event}, got #{announced.inspect}"
        end
      end

      # Requires the optional PaperTrail integration.
      def assert_changes_audit_trail(on: nil, by: nil, **attributes)
        before = ::PaperTrail::Version.maximum(:id) || 0
        yield
        versions = ::PaperTrail::Version.where("id > ?", before)
        versions = versions.where(item_type: on.class.base_class.name, item_id: on.id.to_s) if on
        versions = versions.where(whodunnit: (by.respond_to?(:id) ? by.id : by).to_s) unless by.nil?
        assert versions.where(attributes).exists?, "expected an audit entry, but none matched"
      end

      def assert_matches_catalog
        path = Registry.catalog_path
        assert path.exist?, "write the catalog with bin/rails actions:dump"
        assert_equal Registry.catalog_json, path.read, "the catalog is out of date: run bin/rails actions:dump"
      end

      # Checks the same registry promises as the RSpec shared example. An
      # engine's action test may live under test_root or in the engine's own
      # test/actions folder.
      def assert_valid_action_registry(test_root: Rails.root.join("test/actions"))
        refute_empty Registry.check!
        paths = Actions.config.action_paths
        files = Actions.config.strict_action_paths ? Registry.action_files : Registry.actions.map { Registry.source(it) }
        missing = files.map { |file| [file, paths.relative(file).sub_ext("_test.rb")] }
          .reject { |file, test| [Pathname(test_root), paths.for(file).root.join("../../test/actions")].any? { it.join(test).exist? } }
          .map(&:last)
        assert_empty missing, "write #{missing.join(", ")} under #{test_root}"
        invalid = Registry.actions.reject { JSONSchemer.valid_schema?(it.input_schema) }
        assert_empty invalid.map(&:action_name)
        assert_matches_catalog
      end

      private

      def caller_configuration = TestHelper.config
    end
  end
end
