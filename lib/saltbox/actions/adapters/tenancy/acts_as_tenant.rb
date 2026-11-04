require "acts_as_tenant"

module Saltbox
  module Actions
    module Adapters
      module Tenancy
        # Runs every call, actions list and search in the caller's tenant,
        # with ActsAsTenant.with_tenant, around the app's own invocation
        # callbacks. The tenant is the action's current_tenant: by default the
        # record the person's model belongs to through the association
        # acts_as_tenant keeps on it (acts_as_tenant :org gives an Account's
        # org), never ActsAsTenant.tenant_klass, which names whichever model
        # declared last. A person with no tenant is refused, never run
        # unscoped. A system caller keeps the tenant around it, such as a
        # job's. The person is reloaded (Base#refresh_caller) outside any
        # tenant, so require_tenant does not refuse the lookup. Approvals
        # (the :approvals adapter) are kept in the same tenant.
        #
        # @example config/initializers/saltbox_actions.rb
        #   config.adapters = [:pundit, :acts_as_tenant]
        #
        # @example A person with accounts in several tenants
        #   class ApplicationAction < Saltbox::Actions::Base
        #     def current_tenant = current_user.accounts.find_by!(id: current_caller.connection.account_id)
        #   end
        module ActsAsTenant
          # @param person [Object] the caller's user
          # @return [Object, nil] the tenant the person's model belongs to, or nil when it keeps none
          def self.tenant_of(person)
            return unless person.is_a?(ActiveRecord::Base)
            key = person.class.try(:acts_as_tenant_foreign_key) or return
            reflection = person.class.reflect_on_all_associations(:belongs_to).find { it.foreign_key.to_s == key.to_s }
            reflection && person.public_send(reflection.name)
          end

          # @return [Object, nil] the tenant set now
          def self.current = ::ActsAsTenant.current_tenant

          # @param tenant [Object]
          # @yield the work, in the tenant
          # @return [Object] the block's value
          def self.with_tenant(tenant, &) = ::ActsAsTenant.with_tenant(tenant, &)

          # @yield the work, outside any tenant
          # @return [Object] the block's value
          def self.without_tenant(&) = ::ActsAsTenant.without_tenant(&)
        end
      end
    end
  end
end
