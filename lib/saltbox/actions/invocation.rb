module Saltbox
  module Actions
    # The one path every surface runs an action through. Inside the app's
    # set-up for the caller (Configuration#around_invocation) it refuses in a
    # fixed order, checks the input, and runs the action: a read as it is, a
    # change inside its model's transaction that notes every record it
    # changed (see ChangeTracking) and hands them to Configuration#on_changes
    # before commit. The same changes are
    # published as the changes.saltbox_actions notification. Every refusal
    # leaves as an Error.
    class Invocation
      # @return [Class] the action being run
      attr_reader :action
      # @return [Caller] who runs it, as the app refreshed them
      attr_reader :caller
      # @return [Hash, nil] its input, once checked
      attr_reader :arguments

      # @param name [String, Class] the action's name, or the action class
      # @param caller [Caller]
      # @param arguments [Hash]
      # @param expected_kind [Symbol, nil] the kind a generic run tool requires
      # @return [Result]
      # @raise [Error]
      def self.call(name:, caller:, arguments: {}, expected_kind: nil)
        action = name.is_a?(Class) ? name : Registry.fetch(name)
        new(action, caller).call(arguments, expected_kind:)
      end

      # Notes every record changed inside the block, through #note. The
      # changes stay inside one invocation, so there is one collection.
      #
      # @yield the work whose changes are noted
      # @return [Array(Object, Array<Array(String, String, String)>)] the
      #   block's value and each changed record's type, id and event, once
      # @raise [ArgumentError] when a collection is already running
      def self.collect_changes
        raise ArgumentError, "Nested action collection is not supported" if Current.changes
        Current.set(changes: []) do
          result = yield
          [result, Current.changes.uniq { |type, id, _event| [type, id] }]
        end
      end

      # Notes one changed record. ChangeTracking calls it for each record
      # saved or destroyed, and an audit trail may call it for each entry it
      # writes (see Saltbox::Actions::PaperTrail). A note is dropped if the
      # transaction it was made in rolls back. Outside a collection it does
      # nothing.
      #
      # @param item_type [String] the changed record's class name
      # @param item_id [#to_s]
      # @param event_type [String] create, update, destroy or another event
      # @param transaction [ActiveRecord::Transaction] the write's
      #   transaction; pass the model's own in a multi-database app
      # @return [void]
      def self.note(item_type, item_id, event_type, transaction: ActiveRecord::Base.current_transaction)
        return unless Current.changes
        change = [item_type, item_id.to_s, event_type]
        Current.changes.push(change)
        transaction.after_rollback { Current.changes&.delete_if { it.equal?(change) } } if transaction.open?
      end

      # @param action [Class]
      # @param caller [Caller]
      def initialize(action, caller)
        @action = action
        @caller = caller
      end

      # @return [String, nil] this invocation's id, from when it starts; kept
      #   for a hook that runs after it, such as a deferred after_change
      attr_reader :invocation_id

      # @param arguments [Hash]
      # @param expected_kind [Symbol, nil] generic tool kind
      # @return [Result]
      # @raise [Error]
      def call(arguments, expected_kind: nil)
        raise ArgumentError, "Nested action invocations are not supported; compose domain methods" if Current.invocation_id
        Actions.within(@caller) do |fresh|
          @caller = fresh
          @invocation_id = SecureRandom.uuid_v7
          # Approvals are for this call's arguments only.
          @confirmed = Set.new
          Current.set(invocation: self, invocation_id: @invocation_id) do
            refuse!
            if expected_kind && @action.kind != expected_kind
              raise Error::Invalid, "#{@action.action_name} is a #{@action.kind} action; run it with run_#{@action.kind}_action"
            end
            @arguments = @action.validate_arguments(arguments, @caller)
            confirm!(@action)
            run(@arguments)
          end
        end
      rescue Error
        raise
      rescue => error
        mapped = translate(error)
        mapped ? raise(mapped) : raise
      end

      # Refuses a :confirm action the app's Configuration#confirm hook does
      # not approve, when Configuration#enforce_confirm is on and an agent
      # calls. An action approved once in this call is not asked again; the
      # next call on the same Invocation asks afresh.
      # Caller#confirm! calls it for an action named inside another.
      #
      # @param action [Class]
      # @return [void]
      # @raise [Error::ConfirmationRequired, Error]
      def confirm!(action)
        return unless Actions.config.enforce_confirm && @caller.agent? && action.connections == :confirm
        return if @confirmed.include?(action)
        approved = Actions.config.confirm.call(self, action)
        raise Error::ConfirmationRequired.new(details: {"action" => action.action_name}) unless approved == true
        @confirmed << action
      end

      private

      # Refuses in this order, so the first check that fails gives the error:
      # - the action's feature is off for the caller: not_found;
      # - the action's `connections` declaration bars this caller: human_required;
      # - the connection's access does not reach it: Configuration#on_access_refused's error;
      # - the token lacks the scope: insufficient_scope;
      # - the person's role is not allowed the action, or they lack a permission
      #   it declares (unless Configuration#enforce_permissions is off): forbidden.
      # After the input is checked, #confirm! refuses a :confirm action the app
      # has not approved: confirmation_required.
      def refuse!
        raise Error::NotFound unless @action.enabled_for?(@caller)
        raise Error::HumanRequired unless @caller.agent_allowed?(@action)
        raise Actions.config.on_access_refused.call(@caller, @action) unless @caller.reaches?(@action)
        raise Error::InsufficientScope unless @caller.allows?(@action.scope)
        allowed = Actions.config.enforce_permissions ? @action.permitted_for?(@caller) : @action.permitted?(@caller.account)
        raise Error::Forbidden unless allowed
      end

      def run(arguments)
        action = @action.new(actor: @caller, params: Params.new(arguments, action: @action))
        Actions.config.around_run.call(self, -> do
          next action.perform_now if @action.kind == :read
          # Its own savepoint inside a caller's transaction, so a failure
          # undoes the action's writes even when the caller rescues it.
          # The model's own connection, so a model in a second database
          # is rolled back too. Writes on any other connection are not.
          transaction_class.transaction(requires_new: true) do
            result, changes = self.class.collect_changes { action.perform_now }
            Actions.config.on_changes.call(changes, self)
            ActiveSupport::Notifications.instrument("changes.saltbox_actions", action: @action, caller: @caller, changes:)
            # Once the caller's transactions commit too; never on rollback.
            ActiveRecord.after_all_transactions_commit { Actions.config.after_change.call(self, result) }
            result
          end
        end)
      end

      def transaction_class
        model = @action.model
        (model.is_a?(Class) && model < ActiveRecord::Base) ? model : ActiveRecord::Base
      end

      # The Error callers see for an exception raised inside the action, or
      # nil for a bug, which stays a 500.
      def translate(error)
        Actions.config.error_mappings.each do |error_class, mapping|
          error_class = error_class.constantize if error_class.is_a?(String)
          return mapping.call(error) if error.is_a?(error_class)
        end
        case error
        when ActiveRecord::RecordNotFound then Error::NotFound.new
        when ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
          Error::Invalid.new(error.record.errors.full_messages.to_sentence.presence || error.message,
            errors: error.record.errors.to_hash(true).transform_keys(&:to_s).presence)
        when ActiveRecord::DeleteRestrictionError then Error.new(error.message, code: :in_use, status: :unprocessable_content)
        when *@action.authorization_errors then Error::Forbidden.new
        end
      end
    end
  end
end
