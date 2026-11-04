require "digest"
require "json"

module Saltbox
  module Actions
    # A person's approval of one agent call to a :confirm action, kept in the
    # gem's own table, saltbox_action_approvals, as Active Storage keeps its
    # blobs. The :approvals adapter loads it, and Invocation asks
    # Approval.redeem! about each agent's :confirm call. An agent's first call is refused with
    # confirmation_required and left here as a request; the person approves
    # it on one of the app's screens; the same call, with the same arguments,
    # from the same connection and surface, then runs once.
    #
    # `rails g actions:approvals` writes the table's migration.
    # Configuration#approvals names the app's classes: the person (user), the
    # tenant, and the connection. With a tenant, every approval belongs to
    # acts_as_tenant's current tenant, which the :acts_as_tenant adapter sets
    # for every call, and none is seen or redeemed from another.
    #
    # @example config/initializers/saltbox_actions.rb
    #   Saltbox::Actions.configure do |config|
    #     config.adapters = [:pundit, :acts_as_tenant, :approvals]
    #     config.approvals = {user: "Account", tenant: "Org", connection: "Oauth::Connection"}
    #   end
    #
    # @example a screen of the person's requests
    #   Saltbox::Actions::Approval.waiting_for(current_user)
    class Approval < ActiveRecord::Base
      self.table_name = "saltbox_action_approvals"

      # How long a request waits for the person.
      class_attribute :request_lifetime, instance_writer: false, default: 1.hour
      # How long an approval waits for the agent to call again.
      class_attribute :approval_lifetime, instance_writer: false, default: 15.minutes

      validates :user_id, :surface, :action_name, :confirms, :arguments_digest, :expires_at, presence: true
      validates :arguments, exclusion: {in: [nil]}
      validates :tenant_id, presence: true, if: -> { self.class.tenanted? }

      scope :unexpired, -> { where(used_at: nil, expires_at: Time.current..) }
      scope :pending, -> { unexpired.where(approved_at: nil) }
      scope :approved, -> { unexpired.where.not(approved_at: nil) }

      class << self
        # Declares the associations Configuration#approvals names. Run by the
        # :approvals adapter once the app has loaded.
        #
        # @param settings [Hash] Configuration#approvals
        # @return [void]
        # @api private
        def install!(settings)
          @settings = settings
          belongs_to :user, class_name: settings.fetch(:user), optional: true
          belongs_to :tenant, class_name: settings[:tenant], optional: true if settings[:tenant]
          belongs_to :connection, class_name: settings[:connection], optional: true if settings[:connection]
        end

        # @return [Boolean] whether approvals are kept per tenant
        def tenanted? = settings[:tenant].present?

        # The tenant approvals are kept in now: acts_as_tenant's.
        #
        # @return [Object] the tenant record
        # @raise [ArgumentError] when approvals are kept per tenant and none is set
        def current_tenant!
          tenant = ::ActsAsTenant.current_tenant if defined?(::ActsAsTenant)
          tenant or raise ArgumentError, "Approvals are kept per tenant (config.approvals names #{settings[:tenant]}), but no tenant is set: " \
            "declare the :acts_as_tenant adapter, which sets it for every call"
        end

        # The current tenant's approvals, or every one when approvals are
        # not kept per tenant.
        #
        # @return [ActiveRecord::Relation]
        def in_tenant = tenanted? ? where(tenant_id: current_tenant!.id) : all

        # The requests waiting for the person, newest first, in the current tenant.
        #
        # @param user [Object] the person
        # @return [ActiveRecord::Relation]
        def waiting_for(user) = in_tenant.pending.where(user_id: user.id).order(created_at: :desc)

        # Lets an agent's :confirm call run when the person approved this
        # exact call, and uses the approval up; otherwise refuses it,
        # carrying the request to approve, which Invocation saves.
        #
        # @param invocation [Invocation] the agent's call
        # @param action [Class] the :confirm action: the call's own, or one Caller#confirm! names
        # @return [true]
        # @raise [Error::ConfirmationRequired] until the person approves
        def redeem!(invocation, action)
          call = matching(invocation, action)
          id = call.approved.pick(:id)
          return true if id && call.approved.where(id:).update_all(used_at: Time.current) == 1
          request = call.pending.first || call.new(agent_name: invocation.caller.agent_name,
            arguments: invocation.arguments.as_json, expires_at: request_lifetime.from_now)
          raise Error::ConfirmationRequired.new(request.refusal_message(invocation.caller.user), details: {"action" => request.confirms}, request:)
        end

        # @param invocation [Invocation]
        # @param action [Class]
        # @return [ActiveRecord::Relation] approvals of this call: the
        #   tenant, person, connection, surface, actions and arguments
        def matching(invocation, action)
          caller = invocation.caller
          in_tenant.where(user_id: caller.user.id, connection_id: caller.connection&.id, surface: caller.surface,
            action_name: invocation.action.action_name, confirms: action.action_name, arguments_digest: digest(invocation.arguments))
        end

        # @param arguments [Hash]
        # @return [String] the same for the same arguments, whatever their order
        def digest(arguments) = Digest::SHA256.hexdigest(JSON.generate(sorted(arguments.as_json)))

        # @return [Hash] Configuration#approvals, as installed
        # @api private
        def settings = @settings || Actions.config.approvals

        private

        def sorted(value)
          case value
          when Hash then value.sort.to_h { |key, item| [key, sorted(item)] }
          when Array then value.map { sorted(it) }
          else value
          end
        end
      end

      # Approves the request: the agent's same call runs once, within
      # approval_lifetime. Only a request still waiting can be approved. It
      # writes with update_all, so the request is approved once even when two
      # answers race: callbacks, validations, optimistic locking
      # (lock_version) and an audit trail (PaperTrail) do not run.
      #
      # @return [void]
      # @raise [ActiveRecord::RecordNotFound] when the request has expired, or was approved or used
      def approve!
        approved_at = Time.current
        expires_at = approval_lifetime.from_now
        answered = self.class.pending.where(id:).update_all(approved_at:, expires_at:, updated_at: approved_at)
        raise ActiveRecord::RecordNotFound.new("This request has expired or was already answered", self.class.name) unless answered == 1
        assign_attributes(approved_at:, expires_at:, updated_at: approved_at)
        clear_changes_information
      end

      # @return [String] the title of the action the person is asked to approve
      def title = Registry.fetch(confirms).title

      # What the agent is told until the person approves: the app's
      # actions.errors.approval_needed, with %{user} (the person, by
      # Configuration#approvals' name method), %{app} and %{url}.
      #
      # @param person [Object] the person asked to approve; the request's user by default
      # @return [String]
      def refusal_message(person = user)
        settings = self.class.settings
        I18n.t("actions.errors.approval_needed", user: person&.public_send(settings.fetch(:name, :to_s)).to_s, app: Actions.config.app_name,
          url: settings[:url].to_s, default: "#{Error::ConfirmationRequired.new.message} Then call it again with the same arguments.")
      end

      # Saved in the current tenant.
      before_validation(on: :create) { self.tenant_id ||= self.class.current_tenant!.id if self.class.tenanted? }
    end
  end
end
