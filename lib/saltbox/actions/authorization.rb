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
    # - authorization_problems: what the boot check reports, such as a missing policy;
    # - permitted_attribute_names_for(principal, record), for the input schema;
    # - authorization_errors: the library's refusal, answered as forbidden.
    #
    # Without an adapter, every action is allowed and the boot check asks
    # for no policy.
    module Authorization
      autoload :Pundit, "saltbox/actions/authorization/pundit"
      autoload :ActionPolicy, "saltbox/actions/authorization/action_policy"

      # The boot check for an adapter whose rules live in policy classes,
      # one per model. The adapter defines policy_class, policy_rule?(rule)
      # and policy_label.
      module Policies
        extend ActiveSupport::Concern

        class_methods do
          # @return [Array<String>] a missing policy or rule, and the fix
          def authorization_problems
            return [] unless model
            problems = []
            if declared_name && declared_query.nil?
              return ["#{model.name} is its model: name the policy rule, authorize :show? or another"]
            elsif more_than_verb? && declared_query.nil? && !declared_name
              problems << "#{action_words.join(" ")} says more than #{verb}: name the policy query, authorize :#{verb}? or another"
            end
            if policy_class.nil?
              problems << "#{model.name} has no #{policy_label} policy: add #{model.name}Policy, or include another authorization adapter (see the README)"
            elsif !policy_rule?(policy_query)
              problems << "#{policy_class}##{policy_query} is missing: add it, or authorize another query"
            end
            problems
          end
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
