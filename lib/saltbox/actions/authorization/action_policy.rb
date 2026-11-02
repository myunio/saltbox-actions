require "action_policy"

module Saltbox
  module Actions
    module Authorization
      # Authorizes actions with ActionPolicy. Events::UpdateAction asks
      # EventPolicy's update? rule (aliases and default rules apply), and
      # #perform must call authorize and policy_scope (authorized_scope).
      # The policy's authorization context is the caller's account as
      # `user`; override authorization_context_for to add more.
      #
      # Policies are looked up in the action's policy namespace
      # (Policies#policy_namespace), strictly: Admin::Projects::ListAction
      # asks Admin::ProjectPolicy, and never falls back to ProjectPolicy.
      #
      # ActionPolicy has no permitted_attributes. A policy that defines one,
      # returning the field names the person may set, gives create and update
      # actions their fields; otherwise an action names them with `accepts`.
      module ActionPolicy
        extend ActiveSupport::Concern

        # Included after ActionPolicy's own modules, so it wins over them.
        module Namespace
          private

          def authorization_namespace = self.class.policy_namespace_module!

          def authorization_strict_namespace = true
        end

        included do
          include ::ActionPolicy::Behaviour
          include Namespace
          include Policies

          authorize :user, through: :account
        end

        class_methods do
          # @return [Module, nil] the policy namespace, as ActionPolicy's authorization_namespace takes it
          def policy_namespace_module = policy_namespace.presence&.then { it.map { it.to_s.camelize }.join("::").safe_constantize }

          # @return [Module, nil]
          # @raise [ActionPolicy::NotFound] for a namespace no module has, so no policy can be in it
          def policy_namespace_module!
            return if policy_namespace.empty?
            policy_namespace_module || raise(::ActionPolicy::NotFound.new(model, "No module #{policy_namespace.join("/").camelize} holds policies"))
          end

          # @param account [Object]
          # @return [Hash] the policy's authorization context
          def authorization_context_for(account) = {user: account}

          # Whether the person's role allows the action at all, asked of the
          # model's policy before any record is loaded.
          #
          # @param account [Object]
          # @return [Boolean]
          def permitted?(account)
            return true unless model
            policy = policy_class || raise(::ActionPolicy::NotFound.new(model, "Couldn't find #{expected_policy_name} for #{model}"))
            policy.new(model, **authorization_context_for(account)).apply(policy_query!)
          end

          # @return [Class, nil] the model's policy, in the action's policy namespace
          def policy_class
            return unless model
            namespace = policy_namespace_module
            return if namespace.nil? && policy_namespace.any?
            ::ActionPolicy.lookup(model, namespace:, strict_namespace: true, allow_nil: true)
          end

          # @param rule [Symbol]
          # @return [Boolean] whether the policy answers the rule: defined, aliased, or by its default rule
          def policy_rule?(rule)
            policy = policy_class
            return false unless policy
            policy.method_defined?(rule) || !!policy.lookup_alias(rule) || !!policy.lookup_default_rule
          end

          # @return [String]
          def policy_label = "ActionPolicy"

          # @return [Boolean] whether the model's policy defines permitted_attributes
          def supplies_fields? = !!policy_class&.method_defined?(:permitted_attributes)

          # @param principal [Object]
          # @param record [ActiveRecord::Base]
          # @return [Array<String>]
          def permitted_attribute_names_for(principal, record)
            policy = policy_class.new(record, **authorization_context_for(principal))
            policy.respond_to?(:permitted_attributes) ? policy.permitted_attributes.map(&:to_s) : []
          end

          # @return [Array<Class<Exception>>]
          def authorization_errors = [::ActionPolicy::Unauthorized]
        end

        # ActionPolicy's authorize!. With no rule given, it asks the action's
        # own: the one declared with `policy_rule`, otherwise the one for its verb.
        #
        # @param record [Object]
        # @param rule [Symbol, nil]
        # @return [Object] the record
        # @raise [ActionPolicy::Unauthorized]
        def authorize(record, rule = nil, **)
          @_authorization_performed = true
          authorize!(record, to: rule || self.class.policy_query!, **)
          record
        end

        # ActionPolicy's authorized_scope. A model is taken as all its
        # records, as Pundit's policy_scope takes it.
        #
        # @param scope [ActiveRecord::Relation, Class]
        # @return [ActiveRecord::Relation] the records the person may see
        def policy_scope(scope, **)
          @_policy_scoped = true
          authorized_scope(relation(scope), **)
        end

        def skip_authorization = @_authorization_performed = true

        def skip_policy_scope = @_policy_scoped = true

        # @raise [AuthorizationNotPerformedError] when #perform never called authorize
        def verify_authorized
          raise AuthorizationNotPerformedError, "#{self.class.name} never called authorize" unless @_authorization_performed
        end

        # @raise [PolicyScopingNotPerformedError] when #perform never called policy_scope
        def verify_policy_scoped
          raise PolicyScopingNotPerformedError, "#{self.class.name} never called policy_scope" unless @_policy_scoped
        end

        private

        def permitted_attribute_names(record)
          policy = policy_for(record:)
          policy.respond_to?(:permitted_attributes) ? policy.permitted_attributes.map(&:to_s) : []
        end

        def scoped_records(model) = authorized_scope(model.all)

        def relation(scope) = (scope.is_a?(Class) && scope < ActiveRecord::Base) ? scope.all : scope
      end
    end
  end
end
