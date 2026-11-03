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
      autoload :Pundit, "saltbox/actions/authorization/pundit"
      autoload :ActionPolicy, "saltbox/actions/authorization/action_policy"

      # What an adapter whose rules live in policy classes, one per model,
      # shares: the namespace its policies are looked up in, and the
      # rails actions:check check. The adapter defines policy_class,
      # policy_rule?(rule) and policy_label.
      module Policies
        extend ActiveSupport::Concern

        # Guards each action's one warning that its policy is missing.
        # @api private
        WARNING = Mutex.new

        class_methods do
          # The namespace the action's policy is looked up in, as Pundit's
          # authorize [:admin, project] names one. It is the action's outer
          # namespace (Naming#outer_namespace), so Admin::Projects::ListAction
          # asks Admin::ProjectPolicy, everywhere: before any record loads,
          # in authorize and policy_scope, for its fields and for the records
          # a reference may pick. An action with no model has every module
          # it is in, so Admin::CountProjectsAction's authorize Project asks
          # Admin::ProjectPolicy. A missing namespaced policy is never
          # replaced by the model's own: the action fails, and
          # rails actions:check names the policy to add.
          #
          # Declare another when the class's modules are not the right one:
          # a symbol or a module, or false for the model's own policy. The
          # declaration holds for the class that declares it and its
          # subclasses in its modules and below them. A subclass adds the
          # outer modules its name has beyond the declaring class's, so it
          # never inherits a way out of them:
          # - ApplicationAction's `policy_namespace :staff` makes
          #   Admin::Projects::ListAction ask Staff::Admin::ProjectPolicy;
          # - Admin::ApplicationAction's `policy_namespace :staff` makes
          #   Admin::Projects::ListAction ask Staff::ProjectPolicy, and
          #   Admin::Reports::ExportAction on Project ask Staff::Reports::ProjectPolicy;
          # - an Admin:: subclass of Projects::ExportAction, which declares
          #   false, asks Admin::ProjectPolicy.
          #
          # @param value [Symbol, String, Module, false, nil] declares it: :admin, Admin, or false
          # @return [Array<Symbol>] such as [:admin]; [] for the model's own policy
          # @raise [ArgumentError] for a value that names no module, such as "", true or []
          def policy_namespace(value = nil)
            return @declared_policy_namespace = namespace_words(value) unless value.nil?
            declarer = ancestors.find { it.instance_variable_defined?(:@declared_policy_namespace) }
            return outer_namespace.map(&:to_sym) unless declarer
            [*declarer.instance_variable_get(:@declared_policy_namespace), *outer_namespace_below(declarer).map(&:to_sym)]
          end

          # @api private
          # @return [Symbol] the policy rule the action asks
          # @raise [ArgumentError] for an action with a declared name and no policy_rule, naming the fix
          def policy_rule!
            policy_rule || raise(ArgumentError, "#{name}: #{missing_rule}")
          end

          # @api private
          # @param of [Class] the model
          # @return [String] its policy's name in the action's policy namespace, found or not: Admin::ProjectPolicy
          def expected_policy_name(of = model) = [*policy_namespace.map { it.to_s.camelize }, "#{of.name}Policy"].join("::")

          # A reference field's records are picked through the policy
          # namespace too (scoped_records). Checked once the input schema
          # builds; the adapter answers reference_scope?(model) and
          # reference_scope_name(model).
          #
          # @return [Array<String>] each reference field whose namespaced scope does not exist, and the fix
          # @api private
          def reference_problems
            return [] if policy_namespace.empty?
            writable_fields.filter_map do |name, field|
              next if field.reference.nil? || reference_scope?(field.reference)
              "#{name} picks from #{field.reference.name} records through #{reference_scope_name(field.reference)}, which does not exist: " \
                "add it, or declare policy_namespace (see the README)"
            end
          end

          # @api private
          # Whether the action's policy does not exist, as when
          # Reports::ExportAction on Event has no Reports::EventPolicy. Such an
          # action is left out of every actions list, MCP's and the
          # assistant's included, so the others stay listed; running it still
          # fails, and rails actions:check names the policy. The first time,
          # it warns, through the Rails logger once Rails has one.
          #
          # @return [Boolean]
          def policy_missing?
            return false unless model && policy_class.nil?
            warn_policy_missing
            true
          end

          # @return [Array<String>] a missing policy or rule, and the fix
          def authorization_problems
            return [] unless model
            problems = []
            if declared_name && declared_rule.nil?
              return [missing_rule]
            elsif more_than_verb? && declared_rule.nil? && !declared_name
              problems << "#{action_words.join(" ")} says more than #{verb}: name the policy rule, policy_rule :#{verb}? or another"
            end
            if policy_class.nil?
              problems << missing_policy_problem
            elsif !policy_rule?(policy_rule)
              problems << "#{policy_class}##{policy_rule} is missing: add it, or name another with policy_rule"
            end
            if accepted_fields.any? && supplies_fields?
              problems << "#{policy_class}#permitted_attributes says which fields a person may set: remove accepts, so the policy is the one list"
            end
            problems
          end

          private

          def namespace_words(value)
            return [] if value == false
            words = case value
            when Module then value.name.to_s.underscore.split("/", -1)
            when Symbol, String then value.to_s.split("/", -1)
            else []
            end
            return words.map(&:to_sym) if words.any? && words.none?(&:blank?)
            raise ArgumentError, "#{name}: policy_namespace #{value.inspect} names no module: " \
              "declare a symbol such as :admin, a module, or false for the model's own policy"
          end

          # The outer namespace of the modules the action's name has beyond
          # the declaring class's; all of it when the action is not inside them.
          def outer_namespace_below(declarer)
            modules = name.to_s.deconstantize.split("::")
            above = declarer.name.to_s.deconstantize.split("::")
            (modules.first(above.size) == above) ? outer_modules(modules.drop(above.size)) : outer_namespace
          end

          def warn_policy_missing
            first = WARNING.synchronize { !@policy_missing_warned && (@policy_missing_warned = true) }
            return unless first
            message = "saltbox-actions: #{name} is left out of every actions list: #{missing_policy_problem}"
            logger = Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
            logger ? logger.warn(message) : warn(message)
          end

          def missing_rule = "#{model.name} is its model: name the policy rule, policy_rule :show? or another"

          def missing_policy_problem
            if policy_namespace.empty?
              return "#{model.name} has no #{policy_label} policy: add #{expected_policy_name}, or include another authorization adapter (see the README)"
            end
            missing = "#{model.name} has no #{policy_label} policy in #{policy_namespace.join("/")}"
            outer, parent = nested_under
            if parent
              "#{missing}. If #{outer} groups actions under the #{parent.name} model and everyone #{model.name}Policy allows " \
                "may run them, declare policy_namespace false; otherwise add #{expected_policy_name}"
            else
              "#{missing}: add #{expected_policy_name}, or declare policy_namespace (see the README)"
            end
          end

          # Events::Attendees::ListAction on Attendee may be nested under
          # Event, or Events may be a back office named like a model: the
          # class name cannot tell, so the action fails closed, and the check
          # says what false would let in.
          #
          # @return [Array(String, Class), nil] the outer module and the model it names
          def nested_under
            outer = outer_namespace.map(&:camelize).join("::")
            parent = Naming.model_for(outer) if outer.present? && policy_namespace == outer_namespace.map(&:to_sym)
            [outer, parent] if parent && parent != model
          end
        end
      end

      # The defaults Base starts from: no policy, every action allowed.
      module None
        extend ActiveSupport::Concern

        class_methods do
          # @return [Boolean]
          def permitted?(_user) = true

          # @return [Array<String>]
          def authorization_problems = []

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
