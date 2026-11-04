module Saltbox
  module Actions
    # The one path every surface runs an action through. The action is
    # built with the caller, then its invocation callbacks run (Callbacks):
    # the caller is refreshed, each declared adapter sets up, then the app's.
    # Inside them it refuses in a fixed order, checks the input, and runs the
    # action inside its perform callbacks: a read as it is, a change inside
    # its model's transaction that notes every record it changed (see
    # ChangeTracking) and instruments them as the changes.saltbox_actions
    # notification before commit, then runs its commit callbacks once it
    # commits. An error raised inside goes to the action's rescue_from
    # handlers, still inside the invocation callbacks. What leaves is an
    # Error, or a bug, which stays a 500.
    class Invocation
      # @return [Class] the action being run
      attr_reader :action
      # @return [Caller] who runs it, as the app refreshed them
      attr_reader :caller
      # @return [Hash, nil] its input, once checked
      attr_reader :arguments

      # @param action [String, Class] the action's name, or the action class (not an instance)
      # @param caller [Caller]
      # @param arguments [Hash]
      # @param expected_kind [Symbol, nil] the kind a generic run tool requires
      # @return [Result]
      # @raise [Error]
      def self.call(action:, caller:, arguments: {}, expected_kind: nil)
        action = Registry.fetch(action) unless action.is_a?(Class)
        new(action, caller).call(arguments, expected_kind:)
      end

      # Notes every record changed inside the block, through #note. The
      # changes stay inside one invocation, so there is one collection.
      #
      # @yield the work whose changes are noted
      # @return [Array(Object, Array<Array(String, String, String)>)] the
      #   block's value and each changed record's type, id and event, once
      # @raise [ArgumentError] when a collection is already running
      # @api private
      def self.collect_changes
        raise ArgumentError, "Nested action collection is not supported" if Current.changes
        Current.set(changes: []) do
          result = yield
          [result, Current.changes.uniq { |type, id, _event| [type, id] }]
        end
      end

      # Notes one changed record. ChangeTracking calls it for each record
      # saved or destroyed, and an audit trail may call it for each entry it
      # writes (see the :paper_trail adapter). A note is dropped if the
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
      #   for a callback that runs after it, such as a deferred after_commit
      attr_reader :invocation_id

      # @param arguments [Hash]
      # @param expected_kind [Symbol, nil] generic tool kind
      # @return [Result]
      # @raise [Error]
      def call(arguments, expected_kind: nil)
        Adapters.check_authorization!(@action)
        raise ArgumentError, "Nested action invocations are not supported; compose domain methods" if Current.invocation_id
        @invocation_id = SecureRandom.uuid_v7
        # Approvals are for this call's arguments only.
        @confirmed = Set.new
        instance = @action.new(current_caller: @caller, invocation: self)
        Current.set(invocation: self, invocation_id: @invocation_id, arguments_checked: false) do
          instance.run_callbacks_around(:invocation) do
            @caller = instance.current_caller
            run_checked(instance, arguments, expected_kind)
          end
        end
      end

      # Refuses a :confirm action the person has not approved, when
      # Configuration#enforce_confirm is on and an agent calls: with the
      # :approvals adapter, until they approve this exact call
      # (Approval.redeem!); without it, always. An action approved once in
      # this call is not asked again; the next call on the same Invocation
      # asks afresh. Caller#confirm! calls it for an action named inside
      # another.
      #
      # @param action [Class]
      # @return [void]
      # @raise [Error::ConfirmationRequired]
      # @api private
      def confirm!(action)
        return unless Actions.config.enforce_confirm && @caller.agent? && action.agents == :confirm
        return if @confirmed.include?(action)
        raise Error::ConfirmationRequired.new(details: {"action" => action.action_name}) unless Adapters.declared?(:approvals)
        Approval.redeem!(self, action)
        @confirmed << action
      end

      private

      # Everything inside the invocation callbacks. An error raised here
      # goes to the action's rescue_from handlers, once: a handler that
      # raises sends its error on, one that returns answers with what the
      # action rendered, and an error no handler takes leaves as it is.
      # A request a person is asked to approve is saved first, once the
      # change's writes have rolled back, in the caller's tenant.
      def run_checked(instance, arguments, expected_kind)
        refuse!
        if expected_kind && @action.kind != expected_kind
          raise Error::ValidationFailed, "#{@action.action_name} is a #{@action.kind} action; run it with run_#{@action.kind}_action"
        end
        @arguments = @action.validate_arguments(arguments, @caller)
        refuse_lost_defaults!
        instance.assign_input(Params.new(@arguments, action: @action))
        raise Error::ValidationFailed.for(instance.errors) unless instance.valid?
        confirm!(@action)
        run(instance)
      rescue => error
        error.request.save! if error.is_a?(Error::ConfirmationRequired) && error.request&.new_record?
        handled?(instance, error) ? instance.result : raise
      end

      # Whether one of the action's rescue_from handlers took the error. An
      # error is matched by its class, then, as in a controller, by its
      # cause; a gem Error only by its own class, since it is the refusal
      # the action chose, such as a not_found raised to hide a record the
      # policy refused.
      def handled?(instance, error)
        return instance.rescue_with_handler(error) unless error.is_a?(Error)
        handler = instance.handler_for_rescue(error) or return false
        handler.call(error)
        true
      end

      # Refuses in this order, so the first check that fails gives the error:
      # - the action's feature is off for the caller: not_found;
      # - the action's `agents` declaration bars this caller: human_required;
      # - the connection's access does not reach it: Error::OutsideAccess, an insufficient_scope;
      # - the token lacks the scope: insufficient_scope;
      # - the person's role is not allowed the action, or they lack a permission
      #   it declares (unless Configuration#enforce_permissions is off): forbidden.
      # Then the input is checked against the schema and the action's
      # validations: validation_failed. Last, #confirm! refuses a :confirm
      # action the person has not approved: confirmation_required.
      def refuse!
        raise Error::NotFound unless @action.enabled_for?(@caller)
        raise Error::HumanRequired unless @caller.agent_allowed?(@action)
        raise Error::OutsideAccess.new(action: @action) unless @caller.reaches?(@action)
        raise Error::InsufficientScope unless @caller.includes_scope?(@action.required_scope)
        allowed = Actions.config.enforce_permissions ? @action.permitted_for?(@caller) : @action.permitted?(@caller.user)
        raise Error::Forbidden unless allowed
      end

      # Defaults are filled in by Arguments#validate!, which the action's
      # validate_arguments calls through super. An override that skips it
      # and leaves a default out would run the action with nil there, such
      # as a page_size of nil, which pages nothing: that is a bug in the
      # override, raised in every environment.
      #
      # @raise [ArgumentError] naming the override and the defaults it left out
      def refuse_lost_defaults!
        return if Current.arguments_checked
        lost = @action.declared_attributes.select { |_, attribute| attribute.key?(:default) }.keys - @arguments.keys.map(&:to_s)
        return if lost.empty?
        raise ArgumentError, "#{@action.name}.validate_arguments never called super, so #{lost.to_sentence} would have no default: " \
          "call super, which checks the input and fills in each default"
      end

      def run(instance)
        instance.run_callbacks_around(:perform) do
          next instance.perform_now if @action.kind == :read
          # Its own savepoint inside a caller's transaction, so a failure
          # undoes the action's writes even when the caller rescues it.
          # The model's own connection, so a model in a second database
          # is rolled back too. Writes on any other connection are not.
          transaction_class.transaction(requires_new: true) do
            result, changes = self.class.collect_changes { instance.perform_now }
            # Inside the transaction: a subscriber's exception rolls the change back.
            ActiveSupport::Notifications.instrument("changes.saltbox_actions", action: @action, caller: @caller, changes:, invocation_id: @invocation_id)
            # Once the caller's transactions commit too; never on rollback.
            ActiveRecord.after_all_transactions_commit { instance.run_callbacks(:commit) }
            result
          end
        end
      end

      def transaction_class
        model = @action.model
        (model.is_a?(Class) && model < ActiveRecord::Base) ? model : ActiveRecord::Base
      end
    end
  end
end
