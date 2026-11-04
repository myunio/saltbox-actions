module Saltbox
  module Actions
    # The callbacks an app declares in its ApplicationAction, written as
    # ApplicationController's and Active Job's are:
    #
    # - invocation callbacks wrap everything a call does, and every actions
    #   list and search (Saltbox::Actions.within): the place for the
    #   caller's time zone, Current and a rule on a whole surface;
    # - perform callbacks wrap the action's own work, outside its
    #   transaction: the place for an audit trail's request;
    # - commit callbacks run once a change has committed, never on rollback.
    #
    # The gem's own come first: the caller is refreshed (Base#refresh_caller),
    # then each declared adapter's run, in a fixed order whatever the order of
    # config.adapters, then the app's, in the order its classes declare them.
    # Raising in a callback refuses the call.
    #
    # An invocation callback reads the caller (current_caller, current_user,
    # current_tenant), never the action's own declarations: a list or search
    # runs the base class's callbacks on an instance of the base class, with
    # no action.
    #
    # @example
    #   class ApplicationAction < Saltbox::Actions::Base
    #     around_invocation :in_time_zone
    #     before_invocation :require_chat_permission, if: -> { current_caller.surface.assistant? }
    #     around_perform :with_request_context
    #     after_commit :notify_watchers
    #   end
    module Callbacks
      extend ActiveSupport::Concern
      include ActiveSupport::Callbacks

      included do
        define_callbacks :invocation, :perform, skip_after_callbacks_if_terminated: true
        define_callbacks :commit

        # The gem's own, declared here once, so they run first and in this
        # order whatever the order of config.adapters.
        before_invocation :apply_refreshed_caller
        around_invocation :with_current_tenant, if: -> { Adapters.declared?(:acts_as_tenant) }
        around_perform :with_paper_trail_request, if: -> { Adapters.declared?(:paper_trail) }
      end

      class_methods do
        # @!group Invocation callbacks

        # @param filters [Array<Symbol, Proc>] the methods to run, with :if and :unless as for before_action
        # @return [void]
        def before_invocation(*filters, &) = set_callback(:invocation, :before, *filters, &)

        # @param filters [Array<Symbol, Proc>]
        # @return [void]
        def after_invocation(*filters, &) = set_callback(:invocation, :after, *filters, &)

        # @param filters [Array<Symbol, Proc>] each yields to run the rest
        # @return [void]
        def around_invocation(*filters, &) = set_callback(:invocation, :around, *filters, &)

        # @!group Perform callbacks

        # @param filters [Array<Symbol, Proc>]
        # @return [void]
        def before_perform(*filters, &) = set_callback(:perform, :before, *filters, &)

        # @param filters [Array<Symbol, Proc>]
        # @return [void]
        def after_perform(*filters, &) = set_callback(:perform, :after, *filters, &)

        # @param filters [Array<Symbol, Proc>] each yields to run the rest
        # @return [void]
        def around_perform(*filters, &) = set_callback(:perform, :around, *filters, &)

        # @!group Commit callbacks

        # Runs once a change's transaction, and every transaction around it,
        # has committed; never when one rolls back, and never for a read. It
        # may run after the call has ended, outside its invocation callbacks,
        # so it sets up any context it needs itself; current_caller, result
        # and invocation_id stay readable.
        #
        # @param filters [Array<Symbol, Proc>]
        # @return [void]
        def after_commit(*filters, &) = set_callback(:commit, :after, *filters, &)

        # @!endgroup
      end

      # The tenant the call runs in, under the :acts_as_tenant adapter: the
      # record the person's own model belongs to through the association
      # acts_as_tenant keeps on it, such as an Account's org. A system
      # caller keeps the tenant around it, such as a job's. An app whose
      # person has no one tenant, such as a User with accounts in several,
      # defines it. Without the adapter it is nil.
      #
      # @return [Object, nil]
      def current_tenant
        return unless Adapters.declared?(:acts_as_tenant)
        return Adapters::Tenancy::ActsAsTenant.current if current_caller.system?
        Adapters::Tenancy::ActsAsTenant.tenant_of(current_user)
      end

      # @return [String, nil] this call's id, from when it starts; nil in a list or search
      def invocation_id = @invocation&.invocation_id

      # Runs the callbacks of kind around the block, and refuses the call
      # when one halts the chain (throw :abort) before the block runs.
      #
      # @param kind [Symbol] :invocation or :perform
      # @return [Object] the block's value
      # @raise [Error::Forbidden] when a callback halted the chain
      # @api private
      def run_callbacks_around(kind)
        ran = false
        value = nil
        run_callbacks(kind) do
          ran = true
          value = yield
        end
        raise Error::Forbidden unless ran
        value
      end

      private

      # The caller as they stand now, asked first, before every call,
      # actions list and search, so a revoked token or ended access stops
      # the next one. By default:
      # - a caller holding a credential (credential_id or connection) is
      #   refused, since only the app knows its tokens: an app that serves
      #   them defines refresh_caller;
      # - an Active Record person is reloaded, outside any tenant under the
      #   :acts_as_tenant adapter, and refused when they are gone;
      # - any other caller, such as Caller.system's, is kept as it is.
      #
      # @return [Caller] a new caller; a caller cannot change
      # @raise [Error::Unauthorized]
      #
      # @example
      #   def refresh_caller
      #     fresh = User.active.find_by(id: current_user.id) or raise Error::Unauthorized
      #     current_caller.with(user: fresh)
      #   end
      def refresh_caller
        raise Error::Unauthorized if current_caller.credential_id || current_caller.connection
        person = current_user
        return current_caller unless person.is_a?(ActiveRecord::Base) && person.persisted?
        model = person.class
        reload = -> { model.uncached { model.find_by(model.primary_key => person.id) } }
        fresh = Adapters.declared?(:acts_as_tenant) ? Adapters::Tenancy::ActsAsTenant.without_tenant(&reload) : reload.call
        fresh ? current_caller.with(user: fresh) : raise(Error::Unauthorized)
      end

      # Whom the :flipper adapter asks about a feature: one actor, the
      # current tenant when there is one, else the person when Flipper can
      # take them as an actor. One, because Flipper hashes every actor
      # together for a percentage rollout, so adding the person would split
      # a tenant's rollout by person. An app that also turns features on
      # per person defines it.
      #
      # @return [Array<Object>]
      def flipper_actors
        actor = current_tenant || current_user
        actor.respond_to?(:flipper_id) ? [actor] : []
      end

      # @return [Object, nil] the person the :paper_trail adapter stamps on each version: their id
      def user_for_paper_trail = current_user.try(:id)

      # @return [Hash] the columns the :paper_trail adapter sets on each version, beside the person
      def info_for_paper_trail = {}

      # @param key [String]
      # @return [Boolean] whether the feature is on, as the :flipper adapter asks
      # @api private
      def feature_on?(key) = !Adapters.declared?(:flipper) || Adapters::Features::Flipper.enabled?(key, flipper_actors)

      def apply_refreshed_caller
        fresh = refresh_caller
        raise ArgumentError, "#{self.class.name}#refresh_caller returned #{fresh.inspect}: return a Caller, such as current_caller.with(user: fresh)" unless fresh.is_a?(Caller)
        @current_caller = fresh
      end

      def with_current_tenant(&)
        return yield if current_caller.system?
        tenant = current_tenant or raise Error::Forbidden, "#{Actions.config.app_name} found no tenant for this person, so nothing runs."
        Adapters::Tenancy::ActsAsTenant.with_tenant(tenant, &)
      end

      def with_paper_trail_request(&) = Adapters::Audit::PaperTrail.request(whodunnit: user_for_paper_trail, controller_info: info_for_paper_trail, &)
    end
  end
end
