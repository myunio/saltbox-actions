require "action_policy"

module Saltbox
  module Actions
    module Authorization
      # Authorizes actions with ActionPolicy. Events::UpdateAction asks
      # EventPolicy's update? rule (aliases and default rules apply), and
      # #perform must call authorize and policy_scope (authorized_scope).
      # The policy's authorization context is the caller's person as
      # `user`; override authorization_context_for to add more. It is the
      # one context every check gets: the role check before any record
      # loads, the input schema's fields, and authorize, policy_scope,
      # permitted_attributes and references inside #perform.
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

        # Included after ActionPolicy's own modules, so it wins over them:
        # the policy namespace, and the one authorization context.
        module Namespace
          private

          # In a policy namespace the policy is found there by name only
          # (namespaced_policy), for authorize!, allowed_to?, authorized_scope
          # and fields alike. A policy the action's own code passes as with:
          # is used as given. A miss raises for authorized_scope too, which
          # would otherwise fall back to the action as its target and not
          # name the policy.
          #
          # @raise [ActionPolicy::NotFound] when the namespace has no policy for the record, naming it
          def policy_for(record:, with: nil, **)
            return super if with || self.class.policy_namespace.empty?
            with = self.class.namespaced_policy(record) || raise(self.class.namespaced_policy_not_found(record))
            super
          end

          # A cached policy (ActionPolicy's Memoized and ThreadMemoized) is
          # kept per namespace, so Events::ShowAction's never answers
          # Admin::Events::ShowAction.
          def policy_for_cache_key(namespace: self.class.policy_namespace.join("/"), **) = super

          public

          # ActionPolicy's, built by the class's authorization_context_for,
          # so #perform's checks get what permitted? and the schema got.
          #
          # @return [Hash]
          def authorization_context = @_authorization_context ||= self.class.authorization_context_for(current_user)
        end

        included do
          include ::ActionPolicy::Behaviour
          include Namespace
          include Policies
        end

        class_methods do
          # @api private
          # @return [Module, nil] the policy namespace, as ActionPolicy's authorization_namespace takes it
          def policy_namespace_module = policy_namespace.presence&.then { it.map { it.to_s.camelize }.join("::").safe_constantize }

          # The policy's authorization context for the person, in every
          # check. Override it to add a tenant or anything else the
          # policies declare with `authorize`.
          #
          # @param user [Object]
          # @return [Hash] the policy's authorization context
          def authorization_context_for(user) = {user:}

          # Whether the person's role allows the action at all, asked of the
          # model's policy before any record is loaded.
          #
          # @param user [Object]
          # @return [Boolean]
          def permitted?(user)
            return true unless model
            policy = policy_class || raise(namespaced_policy_not_found(model))
            policy.new(model, **authorization_context_for(user)).apply(policy_rule!)
          end

          # @return [Class, nil] the model's policy, in the action's policy namespace
          def policy_class = model && namespaced_policy(model)

          # @api private
          # @param model [Class]
          # @return [Boolean] whether the policy a reference field's records are picked through exists
          def reference_scope?(model) = !namespaced_policy(model).nil?

          # @api private
          # @param model [Class]
          # @return [String]
          def reference_scope_name(model) = expected_policy_name(model)

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

          # @param user [Object]
          # @param record [ActiveRecord::Base]
          # @return [Array<String>]
          def permitted_attribute_names_for(user, record)
            policy = policy_class.new(record, **authorization_context_for(user))
            policy.respond_to?(:permitted_attributes) ? policy.permitted_attributes.map(&:to_s) : []
          end

          # @return [Array<Class<Exception>>]
          def authorization_errors = [::ActionPolicy::Unauthorized]

          # @api private
          # @param record [Object] a record, a model, a relation or a symbol
          # @return [ActionPolicy::NotFound] naming the policy to add: Couldn't find Admin::EventPolicy for Event
          def namespaced_policy_not_found(record)
            model = case record
            when ActiveRecord::Relation then record.klass
            when Class, Symbol then record
            else record.class
            end
            missing = model.is_a?(Class) ? expected_policy_name(model) : "a policy in #{policy_namespace.join("/").camelize}"
            ::ActionPolicy::NotFound.new(record, "Couldn't find #{missing} for #{model.is_a?(Class) ? model.name : model.inspect}")
          end

          # @api private
          # A record's, a model's or a relation's policy, or nil. In a policy
          # namespace it is found there by name, strictly: ActionPolicy's
          # lookup chain without the policy_class a model or record may
          # define, which would name a policy outside it. policy_name is
          # still looked up inside the namespace.
          #
          # @param record [Object]
          # @return [Class, nil]
          def namespaced_policy(record)
            return ::ActionPolicy.lookup(record, strict_namespace: true, allow_nil: true) if policy_namespace.empty?
            namespace = policy_namespace_module or return
            chain = ::ActionPolicy::LookupChain
            (chain.chain - [chain::INSTANCE_POLICY_CLASS, chain::CLASS_POLICY_CLASS]).each do |probe|
              policy = probe.call(record, namespace:, strict_namespace: true)
              return policy if policy&.name&.start_with?("#{namespace.name}::")
            end
            nil
          end
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
          authorize!(record, to: rule || self.class.policy_rule!, **)
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
