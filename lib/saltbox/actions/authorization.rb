module Saltbox
  module Actions
    # What an action asks of its authorization library. The app declares one
    # adapter, and the declaration includes it in Base, so every action has it:
    #
    #   Saltbox::Actions.configure do |config|
    #     config.adapters = [:pundit]  # or [:action_policy]
    #   end
    #
    # The adapters are under adapters/authorization. An adapter is a concern that overrides some of None's methods. On the
    # action:
    # - authorize(record, rule = nil): rule defaults to the action's own;
    # - policy_scope(scope), skip_authorization, skip_policy_scope;
    # - verify_authorized and verify_policy_scoped, run after #perform (a
    #   list action on a model runs only verify_policy_scoped);
    # - permitted_attribute_names(record): the fields the person may set;
    # - scoped_records(model): the records the person may pick, for a reference;
    # and, on the class:
    # - permitted?(user): whether the person's role allows the action at all;
    # - authorization_problems: what rails actions:check reports, such as a missing policy;
    # - supplies_fields?: whether the model's policy says which fields a person
    #   may set; when it does, it is the one list of a create's or update's
    #   fields, and an action may not also name them with `accepts`;
    # - permitted_attribute_names_for(user, record), for the input schema;
    # - authorization_errors: the library's refusal, answered as forbidden.
    #
    # Without an adapter, every action is allowed and rails actions:check asks
    # for no policy.
    module Authorization
      # The defaults Base starts from: no policy, every action allowed.
      module None
        extend ActiveSupport::Concern

        class_methods do
          # @return [Boolean]
          def permitted?(_user) = true

          # @return [Array<String>]
          def authorization_problems = []

          # @api private
          # @return [Array<String>] none: without an adapter every action is allowed
          def permission_problems = []

          # @api private
          # @return [Boolean] false: without a policy, nothing is missing
          def policy_missing? = false

          # @return [Array<String>]
          # @api private
          def reference_problems = []

          # @return [Boolean] false: without an adapter, an action names its model fields with `accepts`
          def supplies_fields? = false

          # @return [nil]
          def policy_class = nil

          # @return [Array<String>]
          def permitted_attribute_names_for(_user, _record) = []

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
