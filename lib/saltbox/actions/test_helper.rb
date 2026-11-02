require "saltbox/actions"
require "saltbox/actions/testing/configuration"
require "saltbox/actions/testing/callers"
require "json_schemer"

module Saltbox
  module Actions
    # Include in ActiveSupport::TestCase and pass action: to #run, or set
    # self.action_class once on the test class. No RSpec dependency is loaded.
    module TestHelper
      include Testing::Callers

      class << self
        def config = @config ||= Testing::Configuration.new

        def configure = yield(config)

        def included(base)
          base.class_attribute :action_class, instance_writer: false
        end
      end

      # Minitest calls #run without a caller to execute the test itself.
      def run(arguments = {}, as: nil, action: action_class)
        return super() unless as
        raise ArgumentError, "pass action: or set self.action_class" unless action
        Invocation.call(name: action, caller: as, arguments:)
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

      # Without `as:` it checks the catalogue's schema, built for
      # Configuration#schema_principal; pass a caller when the policy needs a person.
      def assert_invalid_against_schema(arguments, action: action_class, as: nil)
        assert_raises(Error::Invalid) { Arguments.check(action, arguments, as) }
      end

      def assert_matches_output_schema(result, schema: action_class.output_schema)
        raise ArgumentError, "the action declares no output schema: add returns" unless schema
        body = result.respond_to?(:body) ? result.body : result
        failures = JSONSchemer.schema(schema).validate(body.as_json).map { it["error"] }
        assert_empty failures, "expected the body to match the output schema:\n#{failures.join("\n")}"
      end

      def assert_runnable_by(caller, action: action_class)
        assert Actions.within(caller) { |fresh| action.runnable_for?(fresh) }, "expected #{action.action_name} to be runnable for #{caller.surface}"
      end

      def assert_listed_for(caller, action: action_class)
        assert Actions.within(caller) { |fresh| action.available_to?(fresh) }, "expected #{action.action_name} to be listed for #{caller.surface}"
      end

      def assert_announces_changes(expected = {})
        announced = []
        subscriber = ->(*, payload) { announced.concat(payload[:changes]) }
        ActiveSupport::Notifications.subscribed(subscriber, "changes.saltbox_actions") { yield }
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

      def assert_matches_catalogue
        path = Registry.catalogue_path
        assert path.exist?, "write the catalogue with bin/rails actions:catalogue"
        assert_equal Registry.catalogue_json, path.read, "the catalogue is out of date: run bin/rails actions:catalogue"
      end

      # Checks the same registry promises as the RSpec shared example. An
      # engine's action test may live under test_root or in the engine's own
      # test/actions folder.
      def assert_valid_action_registry(test_root: Rails.root.join("test/actions"))
        refute_empty Registry.check!
        paths = Actions.config.action_paths
        files = Actions.config.every_file_an_action ? Registry.action_files : (Registry.actions - Registry.commands).map { Registry.source(it) }
        missing = files.map { |file| [file, paths.relative(file).sub_ext("_test.rb")] }
          .reject { |file, test| [Pathname(test_root), paths.for(file).root.join("../../test/actions")].any? { it.join(test).exist? } }
          .map(&:last)
        commands = Rails.root.join("app/commands")
        missing += Registry.commands.map { Pathname(Registry.source(it)).relative_path_from(commands).sub_ext("_test.rb") }
          .reject { Pathname(test_root).parent.join("commands", it).exist? }
        assert_empty missing, "write #{missing.join(", ")} under #{test_root}"
        invalid = Registry.actions.reject { JSONSchemer.valid_schema?(it.input_schema) }
        assert_empty invalid.map(&:action_name)
        assert_matches_catalogue
      end

      private

      def caller_configuration = TestHelper.config
    end
  end
end
