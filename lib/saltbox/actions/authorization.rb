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
    # An adapter defines, on the action:
    # - authorize(record, rule = nil): rule defaults to the action's own;
    # - policy_scope(scope), skip_authorization, skip_policy_scope;
    # - verify_authorized and verify_policy_scoped, run after #perform;
    # - permitted_attribute_names(record): the fields the person may set;
    # - scoped_records(model): the records the person may pick, for a reference;
    # and, on the class:
    # - permitted?(account): whether the person's role allows the action at all;
    # - policy_class, policy_rule?(rule), and policy_label for boot errors;
    # - permitted_attribute_names_for(principal, record), for the input schema;
    # - authorization_errors: the library's refusal, answered as forbidden.
    #
    # Without an adapter, every action is allowed and has no policy.
    module Authorization
      autoload :Pundit, "saltbox/actions/authorization/pundit"
      autoload :ActionPolicy, "saltbox/actions/authorization/action_policy"

      # The defaults Base starts from: no policy, every action allowed.
      module None
        extend ActiveSupport::Concern

        class_methods do
          # @return [Boolean]
          def permitted?(_account) = true

          # @return [nil]
          def policy_class = nil

          # @return [Boolean]
          def policy_rule?(_rule) = false

          # @return [String]
          def policy_label = "authorization"

          # @return [Array<String>]
          def permitted_attribute_names_for(_principal, _record) = []

          # @return [Array<Class<Exception>>]
          def authorization_errors = []
        end

        def authorize(record, _rule = nil) = record

        def policy_scope(scope) = scope

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
