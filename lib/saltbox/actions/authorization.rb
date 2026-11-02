module Saltbox
  module Actions
    # What an action asks of its authorization library. The app's base class
    # includes one adapter, the way a controller includes Pundit:
    #
    #   class ApplicationAction < Saltbox::Actions::Base
    #     include Saltbox::Actions::Authorization::Pundit         # or
    #     include Saltbox::Actions::Authorization::ActionPolicy
    #   end
    #
    # An adapter is a concern that overrides some of None's methods. On the
    # action:
    # - authorize(record, rule = nil): rule defaults to the action's own;
    # - policy_scope(scope), skip_authorization, skip_policy_scope;
    # - verify_authorized and verify_policy_scoped, run after #perform (a
    #   list action runs only verify_policy_scoped);
    # - permitted_attribute_names(record): the fields the person may set;
    # - scoped_records(model): the records the person may pick, for a reference;
    # and, on the class:
    # - permitted?(account): whether the person's role allows the action at all;
    # - authorization_problems: what rails actions:check reports, such as a missing policy;
    # - supplies_fields?: whether the model's policy says which fields a person
    #   may set; when it does, it is the one list of a create's or update's
    #   fields, and an action may not also name them with `accepts`;
    # - permitted_attribute_names_for(principal, record), for the input schema;
    # - authorization_errors: the library's refusal, answered as forbidden.
    #
    # Without an adapter, every action is allowed and rails actions:check asks
    # for no policy.
    module Authorization
      autoload :Pundit, "saltbox/actions/authorization/pundit"
      autoload :ActionPolicy, "saltbox/actions/authorization/action_policy"

      # What an adapter whose rules live in policy classes, one per model,
      # shares: the namespace its policies are looked up in, and the
      # rails actions:check check. The adapter defines policy_class,
      # policy_rule?(rule) and policy_label.
      module Policies
        extend ActiveSupport::Concern

        included do
          class_attribute :_policy_namespace, instance_accessor: false, instance_predicate: false
        end

        class_methods do
          # The namespace the action's policy is looked up in, as Pundit's
          # authorize [:admin, project] names one. It is the action's outer
          # namespace (Naming#outer_namespace), so Admin::Projects::ListAction
          # asks Admin::ProjectPolicy, everywhere: before any record loads,
          # in authorize and policy_scope, for its fields and for the records
          # a reference may pick. A missing namespaced policy is never
          # replaced by the model's own: the action fails, and
          # rails actions:check names the policy to add.
          #
          # Declare another when the class's modules are not the right one:
          # a symbol or a module, or false for the model's own policy.
          # Inherited, as policy_rule is.
          #
          # @param value [Symbol, String, Module, false, nil] declares it: :admin, Admin, or false
          # @return [Array<Symbol>] such as [:admin]; [] for the model's own policy
          def policy_namespace(value = nil)
            return _policy_namespace || outer_namespace.map(&:to_sym) if value.nil?
            words = value.is_a?(Module) ? value.name.underscore.split("/") : value.to_s.split("/")
            self._policy_namespace = (value == false) ? [] : words.map(&:to_sym)
          end

          # @return [Symbol] the policy rule the action asks
          # @raise [ArgumentError] for an action with a declared name and no policy_rule, naming the fix
          def policy_query!
            policy_query || raise(ArgumentError, "#{name}: #{missing_rule}")
          end

          # @return [String] the policy's name, found or not: Admin::ProjectPolicy
          def expected_policy_name = [*policy_namespace.map { it.to_s.camelize }, "#{model.name}Policy"].join("::")

          # @return [Array<String>] a missing policy or rule, and the fix
          def authorization_problems
            return [] unless model
            problems = []
            if declared_name && declared_query.nil?
              return [missing_rule]
            elsif more_than_verb? && declared_query.nil? && !declared_name
              problems << "#{action_words.join(" ")} says more than #{verb}: name the policy rule, policy_rule :#{verb}? or another"
            end
            if policy_class.nil? && policy_namespace.any?
              problems << "#{model.name} has no #{policy_label} policy in #{policy_namespace.join("/")}: " \
                "add #{expected_policy_name}, or declare policy_namespace (see the README)"
            elsif policy_class.nil?
              problems << "#{model.name} has no #{policy_label} policy: add #{expected_policy_name}, or include another authorization adapter (see the README)"
            elsif !policy_rule?(policy_query)
              problems << "#{policy_class}##{policy_query} is missing: add it, or name another with policy_rule"
            end
            if accepted_fields.any? && supplies_fields?
              problems << "#{policy_class}#permitted_attributes says which fields a person may set: remove accepts, so the policy is the one list"
            end
            problems
          end

          private

          def missing_rule = "#{model.name} is its model: name the policy rule, policy_rule :show? or another"
        end
      end

      # The defaults Base starts from: no policy, every action allowed.
      module None
        extend ActiveSupport::Concern

        class_methods do
          # @return [Boolean]
          def permitted?(_account) = true

          # @return [Array<String>]
          def authorization_problems = []

          # @return [Boolean] false: without an adapter, an action names its model fields with `accepts`
          def supplies_fields? = false

          # @return [nil]
          def policy_class = nil

          # @return [Array<String>]
          def permitted_attribute_names_for(_principal, _record) = []

          # @return [Array<Class<Exception>>]
          def authorization_errors = []
        end

        def authorize(record, _rule = nil) = record

        # A model is taken as all its records, as Pundit's policy_scope takes it.
        #
        # @param scope [ActiveRecord::Relation, Class]
        # @return [ActiveRecord::Relation]
        def policy_scope(scope) = (scope.is_a?(Class) && scope < ActiveRecord::Base) ? scope.all : scope

        def skip_authorization = nil

        def skip_policy_scope = nil

        def verify_authorized = nil

        def verify_policy_scoped = nil

        def permitted_attribute_names(_record) = []

        def scoped_records(model) = model.all
      end
    end
  end
end
