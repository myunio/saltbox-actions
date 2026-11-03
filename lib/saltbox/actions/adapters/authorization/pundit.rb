require "pundit"
require "saltbox/actions/adapters/authorization/policies"

module Saltbox
  module Actions
    module Adapters
      module Authorization
        # Authorizes actions with Pundit. Events::UpdateAction asks
        # EventPolicy#update?, and #perform must call authorize and
        # policy_scope, as Pundit's verify_authorized and verify_policy_scoped
        # check after a controller action. The person is the caller's user,
        # (pundit_user). An action with a policy namespace
        # (Policies#policy_namespace) asks it the way authorize [:admin, record]
        # does: Admin::Projects::UpdateAction asks Admin::ProjectPolicy#update?.
        module Pundit
          extend ActiveSupport::Concern
          include ::Pundit::Authorization
          include Policies

          # Pundit's own permitted_attributes reads a controller's params; an
          # action's input has already passed its schema (see Permitting).
          define_method(:permitted_attributes, Permitting.instance_method(:permitted_attributes))

          class_methods do
            # Whether the person's role allows the action at all, asked of the
            # model's policy before any record is loaded. An action with no
            # model has no policy to ask: it is allowed only when it declares
            # its permissions (Policies#permission_problems).
            #
            # @param user [Object]
            # @return [Boolean]
            def permitted?(user)
              return !permissions.nil? unless model
              ::Pundit.policy!(user, policy_target(model)).public_send(policy_rule!)
            end

            # @return [Class, nil] the model's Pundit policy, in the action's policy namespace
            def policy_class = model && ::Pundit::PolicyFinder.new(policy_target(model)).policy

            # @api private
            # @param model [Class]
            # @return [Boolean] whether the scope a reference field's records are picked through exists
            def reference_scope?(model) = !::Pundit::PolicyFinder.new(policy_target(model)).scope.nil?

            # @api private
            # @param model [Class]
            # @return [String]
            def reference_scope_name(model) = "#{expected_policy_name(model)}::Scope"

            # @api private
            # @param record [Object] a record, a model or a scope
            # @return [Object, Array] what Pundit is asked about: [:admin, record] in the namespace admin,
            #   otherwise the record; an array as given
            def policy_target(record) = (record.is_a?(Array) || policy_namespace.empty?) ? record : [*policy_namespace, record]

            # @param rule [Symbol]
            # @return [Boolean] whether the policy defines the rule
            def policy_rule?(rule) = !!policy_class&.method_defined?(rule)

            # @return [String]
            def policy_label = "Pundit"

            # @return [Boolean] whether the model's policy defines permitted_attributes
            def supplies_fields? = !!policy_class&.method_defined?(:permitted_attributes)

            # @param user [Object]
            # @param record [ActiveRecord::Base]
            # @return [Array<String>]
            def permitted_attribute_names_for(user, record)
              ::Pundit.policy!(user, policy_target(record)).permitted_attributes.map(&:to_s)
            end

            # @return [Array<Class<Exception>>]
            def authorization_errors = [::Pundit::NotAuthorizedError]
          end

          private

          def pundit_user = current_user

          # Pundit's authorize. With no rule given, it asks the action's own:
          # the one declared with `policy_rule`, otherwise the one for its verb.
          # A delete action asks destroy?.
          def authorize(record, query = nil, policy_class: nil)
            super(policy_class ? record : self.class.policy_target(record), query || self.class.policy_rule!, policy_class:)
          end

          # Pundit's policy, in the action's policy namespace.
          def policy(record) = super(self.class.policy_target(record))

          # Pundit's policy_scope, in the action's policy namespace.
          def policy_scope(scope, policy_scope_class: nil)
            super(policy_scope_class ? scope : self.class.policy_target(scope), policy_scope_class:)
          end

          def permitted_attribute_names(record) = policy(record).permitted_attributes.map(&:to_s)

          def scoped_records(model) = ::Pundit.policy_scope!(current_user, self.class.policy_target(model))
        end
      end
    end
  end
end
