require "pundit"

module Saltbox
  module Actions
    module Authorization
      # Authorizes actions with Pundit. Events::UpdateAction asks
      # EventPolicy#update?, and #perform must call authorize and
      # policy_scope, as Pundit's verify_authorized and verify_policy_scoped
      # check after a controller action. The person is the caller's account
      # (pundit_user).
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
          # model is always allowed.
          #
          # @param account [Object]
          # @return [Boolean]
          def permitted?(account)
            return true unless model
            ::Pundit.policy!(account, model).public_send(policy_query)
          end

          # @return [Class, nil] the model's Pundit policy
          def policy_class = model && ::Pundit::PolicyFinder.new(model).policy

          # @param rule [Symbol]
          # @return [Boolean] whether the policy defines the rule
          def policy_rule?(rule) = !!policy_class&.method_defined?(rule)

          # @return [String]
          def policy_label = "Pundit"

          # @return [Boolean] whether the model's policy defines permitted_attributes
          def supplies_fields? = !!policy_class&.method_defined?(:permitted_attributes)

          # @param principal [Object]
          # @param record [ActiveRecord::Base]
          # @return [Array<String>]
          def permitted_attribute_names_for(principal, record)
            ::Pundit.policy!(principal, record).permitted_attributes.map(&:to_s)
          end

          # @return [Array<Class<Exception>>]
          def authorization_errors = [::Pundit::NotAuthorizedError]
        end

        private

        def pundit_user = account

        # Pundit's authorize. With no rule given, it asks the action's own:
        # the one declared with `policy_rule`, otherwise the one for its verb.
        # A delete action asks destroy?.
        def authorize(record, query = nil, policy_class: nil)
          super(record, query || self.class.policy_query, policy_class:)
        end

        def permitted_attribute_names(record) = policy(record).permitted_attributes.map(&:to_s)

        def scoped_records(model) = ::Pundit.policy_scope!(account, model)
      end
    end
  end
end
