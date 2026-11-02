require "json_schemer"

module Saltbox
  module Actions
    module RSpec
      # Matchers for actions, in the style of rspec-rails' have_http_status.
      # The refusal matchers take a block, as raise_error does, or the Error
      # itself.
      module Matchers
        # Runs a block, or takes a value, and gives back the Error it raised or
        # was, or nil.
        module Outcome
          private

          def outcome(actual)
            return actual if actual.is_a?(Error)
            return unless actual.respond_to?(:call)
            actual.call
            nil
          rescue Error => error
            error
          end
        end

        # @see Matchers#be_refused
        class BeRefused
          include ::RSpec::Matchers::Composable
          include Outcome

          def initialize(code = nil) = @code = code&.to_s

          # @param code [Symbol, String] the error code: forbidden, human_required, not_found…
          # @return [self]
          def with(code)
            @code = code.to_s
            self
          end

          def supports_block_expectations? = true

          def matches?(actual)
            @error = outcome(actual)
            @error && (@code.nil? || @error.code == @code)
          end

          def does_not_match?(actual)
            @error = outcome(actual)
            @code ? @error&.code != @code : @error.nil?
          end

          def failure_message
            return "expected the action to be refused#{" with #{@code}" if @code}, but it ran" unless @error
            "expected the action to be refused with #{@code}, but it was refused with #{@error.code}: #{@error.message}"
          end

          def failure_message_when_negated
            "expected the action not to be refused#{" with #{@code}" if @code}, but it was: #{@error.code}: #{@error.message}"
          end

          def description = "be refused#{" with #{@code}" if @code}"
        end

        # @see Matchers#have_field_errors
        class HaveFieldErrors
          include ::RSpec::Matchers::Composable
          include Outcome

          def initialize(fields) = @fields = fields.map(&:to_s)

          def supports_block_expectations? = true

          def matches?(actual)
            @error = outcome(actual)
            @error.is_a?(Error) && @error.errors.present? && (@fields - @error.errors.keys).empty?
          end

          def failure_message
            return "expected field errors on #{@fields.join(", ")}, but the action ran" unless @error
            "expected field errors on #{@fields.join(", ")}, got #{@error.code}: #{@error.errors.inspect}"
          end

          def description = "have field errors on #{@fields.join(", ")}"
        end

        # @see Matchers#be_invalid_against_schema
        class BeInvalidAgainstSchema
          include ::RSpec::Matchers::Composable

          def initialize(action) = @action = action

          def matches?(arguments)
            @arguments = arguments
            Arguments.for(@action).validate!(arguments)
            false
          rescue Error::Invalid => error
            @error = error
            true
          end

          def failure_message = "expected #{@action.action_name}'s input schema to refuse #{@arguments.inspect}, but it took it"

          def failure_message_when_negated = "expected #{@action.action_name}'s input schema to take #{@arguments.inspect}: #{@error.message}"

          def description = "be invalid against #{@action.action_name}'s input schema"
        end

        # @see Matchers#match_output_schema
        class MatchOutputSchema
          include ::RSpec::Matchers::Composable

          def initialize(schema) = @schema = schema

          def matches?(result)
            raise ArgumentError, "the action declares no output schema: add returns" unless @schema
            body = result.respond_to?(:body) ? result.body : result
            @failures = JSONSchemer.schema(@schema).validate(body.as_json).map { it["error"] }
            @failures.empty?
          end

          def failure_message = "expected the body to match the output schema:\n#{@failures.join("\n")}"

          def description = "match the output schema"
        end

        # @see Matchers#change_audit_trail
        class ChangeAuditTrail
          include ::RSpec::Matchers::Composable

          def initialize = @expected = {}

          # @param record [ActiveRecord::Base] the record the entry is for
          def on(record) = tap { @record = record }

          # @param account [Object] the person named on the entry
          def by(account) = tap { @whodunnit = account.respond_to?(:id) ? account.id : account }

          # @param attributes [Hash] other columns the entry must hold, such as agent: "Claude"
          def with(**attributes) = tap { @expected = attributes }

          def supports_block_expectations? = true

          def matches?(block)
            before = ::PaperTrail::Version.maximum(:id) || 0
            block.call
            @versions = ::PaperTrail::Version.where("id > ?", before)
            @versions = @versions.where(item_type: @record.class.base_class.name, item_id: @record.id.to_s) if @record
            @versions = @versions.where(whodunnit: @whodunnit.to_s) unless @whodunnit.nil?
            @versions = @versions.where(@expected) if @expected.any?
            @versions.exists?
          end

          def failure_message = "expected an audit entry#{" on #{@record.class.name} #{@record.id}" if @record}#{" by #{@whodunnit}" if @whodunnit}#{" with #{@expected}" if @expected.any?}, but none was written"

          def failure_message_when_negated = "expected no audit entry, but #{@versions.count} were written"

          def description = "change the audit trail"
        end

        # @see Matchers#announce_changes
        class AnnounceChanges
          include ::RSpec::Matchers::Composable

          # @param expected [Hash{Class, ActiveRecord::Base => Symbol, String}] records or models, and the event
          def initialize(expected) = @expected = expected

          def supports_block_expectations? = true

          def matches?(block)
            @announced = []
            subscriber = ->(*, payload) { @announced.concat(payload[:changes]) }
            ActiveSupport::Notifications.subscribed(subscriber, "changes.saltbox_actions") { block.call }
            @missing = @expected.reject do |target, event|
              type, id = target.is_a?(Class) ? [target.name, nil] : [target.class.name, target.id.to_s]
              @announced.any? { |t, i, e| t == type && (id.nil? || i.to_s == id) && e.to_s == event.to_s }
            end
            @expected.empty? ? @announced.any? : @missing.empty?
          end

          def failure_message = "expected the action to announce #{@missing.inspect}, but it announced #{@announced.inspect}"

          def failure_message_when_negated = "expected the action to announce no changes, but it announced #{@announced.inspect}"

          def description = "announce changes"
        end

        # @see Matchers#be_runnable_by
        class BeRunnableBy
          include ::RSpec::Matchers::Composable

          def initialize(caller, listed_only:)
            @caller = caller
            @listed_only = listed_only
          end

          def matches?(action)
            @action = action
            Actions.within(@caller) { |fresh| @listed_only ? action.available_to?(fresh) : action.runnable_for?(fresh) }
          end

          def failure_message = "expected #{@action.action_name} to be #{verb} for #{@caller.surface}, but it is not"

          def failure_message_when_negated = "expected #{@action.action_name} not to be #{verb} for #{@caller.surface}, but it is"

          def description = "be #{verb} for the caller"

          private

          def verb = @listed_only ? "listed" : "runnable"
        end

        # Passes when the action refuses; `.with(code)` names the refusal.
        #
        # @example
        #   expect { run(arguments, as: as_mcp(manager)) }.to be_refused.with(:human_required)
        def be_refused = BeRefused.new

        # @return [BeRefused] refused as not_found
        def be_not_found = BeRefused.new(:not_found)

        # Passes when the action refuses its input naming each field.
        #
        # @example
        #   expect { run({title: ""}, as: as_screen(manager)) }.to have_field_errors(:title)
        def have_field_errors(*fields) = HaveFieldErrors.new(fields)

        # Passes when the action's input schema refuses the arguments, before
        # any caller is checked.
        #
        # @example
        #   expect(capacity: "lots").to be_invalid_against_schema
        def be_invalid_against_schema(action = described_class) = BeInvalidAgainstSchema.new(action)

        # Passes when the result's body matches the schema the action declares with `returns`.
        #
        # @example
        #   expect(run({id: event.id}, as: as_api(manager))).to match_output_schema
        def match_output_schema(schema = described_class.output_schema) = MatchOutputSchema.new(schema)

        # Passes when the block writes a PaperTrail entry; narrow it with on, by and with.
        #
        # @example
        #   expect { run(arguments, as: as_mcp(manager)) }.to change_audit_trail.on(event).by(manager).with(agent: "RSpec agent")
        def change_audit_trail = ChangeAuditTrail.new

        # Passes when the change announces each record or model with its event.
        #
        # @example
        #   expect { run(arguments, as: as_screen(manager)) }.to announce_changes(event => :update)
        def announce_changes(expected = {}) = AnnounceChanges.new(expected)

        # Passes when the caller may run the action: listed for them, and not barred by `connections`.
        #
        # @example
        #   expect(described_class).not_to be_runnable_by(as_assistant(manager))
        def be_runnable_by(caller) = BeRunnableBy.new(caller, listed_only: false)

        # Passes when the actions list shows the action to the caller.
        def be_listed_for(caller) = BeRunnableBy.new(caller, listed_only: true)
      end
    end
  end
end
