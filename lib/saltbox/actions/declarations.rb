module Saltbox
  module Actions
    # The settings an action declares at the top of its class, for what its
    # class name and its verb cannot give. Naming reads everything else from
    # the name; Inputs declares its input.
    # - `agents`: whether agents and scripts may run it, when its verb's
    #   default is not right.
    # - `action_name`, `title`, `description` (Naming): for an app whose names are already public.
    # - `kind`: read, change or destructive, for a verb not in the verb table.
    # - `idempotent`: whether calling it again with the same input changes nothing more,
    #   when its verb's default is not right.
    # - `policy_rule`: the policy rule, when the verb's own is not the right one.
    # - `permission`: the permission keys a person needs to see and run it.
    # - `featured`: list the action as an MCP tool of its own.
    # - `feature`: the feature flag the action needs.
    # - `summary`: the fields a list sends agents, and the CLI's columns.
    # - `cli`: the CLI's whole command.
    # - `output_schema`: the JSON Schema of the body it renders.
    #
    # What decides who may run an action (agents, policy_rule,
    # permission, feature) and how agents treat it (idempotent, featured) is
    # inherited, as class_attribute is: a subclass runs under its parent's
    # rules until it declares its own. What names it (action_name, title,
    # description, cli, kind, summary, output_schema) belongs to its own class.
    module Declarations
      extend ActiveSupport::Concern

      AGENT_RULES = %i[allowed confirm never].freeze

      included do
        class_attribute :_agents, :_declared_rule, :_idempotent, :_featured, :_feature, :_permissions,
          instance_accessor: false, instance_predicate: false
      end

      class_methods do
        # Whether a caller other than a person on the app's screens may run the
        # action: the CLI, an AI agent over MCP, a script on the API, the chat
        # assistant, or a browser assistant on the page. Its verb gives the
        # default: :confirm for a destructive action, :allowed for the rest,
        # unless define_verb gave the verb its own. An action declares it only
        # where it departs from that.
        # - :allowed: they may run it.
        # - :confirm: an agent is told to ask the person first. The chat
        #   assistant never runs it. With Configuration#enforce_confirm on,
        #   the server refuses it until the app's confirm hook approves.
        # - :never: only the person, on a screen.
        #
        # @param rule [Symbol, nil] :allowed, :confirm or :never
        # @return [Symbol, nil] nil only for an action whose kind is unknown
        def agents(rule = nil)
          unless rule
            return _agents if _agents
            return verb_rule[:agents] if verb_rule&.key?(:agents)
            return kind && ((kind == :destructive) ? :confirm : :allowed)
          end
          raise ArgumentError, "agents is :allowed, :confirm or :never, not #{rule.inspect}" unless AGENT_RULES.include?(rule)
          self._agents = rule
        end

        # @return [Symbol, nil] the rule declared with `agents`, in this class or a parent
        def declared_agents = _agents

        # Declares the kind of an action whose verb is not in the verb table.
        #
        # @param value [Symbol] :read, :change or :destructive
        # @return [Symbol]
        def kind(value = nil)
          return super() unless value
          raise ArgumentError, "kind is :read, :change or :destructive, not #{value.inspect}" unless Naming::KINDS.include?(value)
          @declared_kind = value
        end

        # @return [Symbol, nil] the kind declared with `kind`
        def declared_kind = @declared_kind

        # Declares the policy rule the action asks. An action named with more
        # than a verb, or with a verb outside the verb table, must declare one:
        # Events::ShowAttendeesAction asks view_attendees?. Called with
        # nothing, it returns the rule the action asks: the declared one,
        # otherwise its verb's (destroy? for delete, "<verb>?" for a verb with
        # no rule of its own). An action with a declared name has only the
        # declared one.
        #
        # @param rule [Symbol, nil]
        # @return [Symbol, nil]
        def policy_rule(rule = nil)
          return self._declared_rule = rule if rule
          declared_rule || verb_policy_rule
        end

        # @api private
        # @return [Symbol, nil] the rule declared with `policy_rule`
        def declared_rule = _declared_rule

        # Declares whether calling the action again with the same input
        # changes nothing more than the first call did, when its verb's
        # default is not right.
        #
        # @param value [Boolean]
        # @return [Boolean]
        def idempotent(value = true) = self._idempotent = value

        # @return [Boolean] the declared value; otherwise the verb's, or true for any other read
        def idempotent?
          return _idempotent unless _idempotent.nil?
          verb_rule ? verb_rule.fetch(:idempotent) : kind == :read
        end

        # Lists the action as an MCP tool of its own. Other actions are reached
        # through find_action. Keep these to about fifteen.
        #
        # @return [void]
        def featured = self._featured = true

        # @return [Boolean] whether the action is an MCP tool of its own
        def featured? = _featured || false

        # The feature flag the action needs. While the flag is off for the
        # caller, every caller gets not_found and the actions list leaves the
        # action out. Configuration#validate_feature checks the key.
        #
        # @param key [String, nil]
        # @return [String, nil]
        def feature(key = nil)
          return _feature unless key
          Actions.config.validate_feature.call(key)
          self._feature = key
        end

        # Declares a record's summary: the fields a list action sends agents
        # in place of its view, and the columns the CLI prints. Declared in
        # the base class with the model first, it serves every action of
        # that model; declared in an action, it serves that action alone.
        # Called with nothing, it returns the action's summary: its own, else
        # the nearest base class's for its model, else nil.
        #
        # @param fields [Array<Class, Symbol>] the model, in the base class only, then the record's own
        #   attributes or methods
        # @param computed [Hash{Symbol => #call}] fields computed from the record
        # @return [Summary, nil]
        #
        # @example In ApplicationAction, for every Event action
        #   summary Event, :id, :title, :starts_on, full: ->(event) { event.attendees_count >= event.capacity }
        # @example In one action
        #   summary :id, :title
        def summary(*fields, **computed)
          return @summary || inherited_summary if fields.empty? && computed.empty?
          return @summary = Summary.build(fields, computed) unless fields.first.is_a?(Class)
          model = fields.shift
          raise ArgumentError, "summary #{model} names no field" if fields.empty? && computed.empty?
          model_summaries[model.name] = Summary.build(fields, computed)
        end

        # @return [Boolean] whether agents get summaries in place of the view: an action whose class
        #   name's verb is list (Events::ListAction, or a renamed Reports::ListUpcomingAction that
        #   declares its model), with a summary
        def summarizes_list? = verb == "list" && !model.nil? && !summary.nil?

        # @return [Hash{String => Summary}] the summaries declared here for each model, by its name
        def model_summaries = @model_summaries ||= {}

        # Declares the whole CLI command, for an app whose commands are
        # already in use: the words people type, other words for it, and the
        # arguments taken by position. Its table's columns are the summary.
        #
        # @param command [String] such as "invoices send"
        # @param aliases [Array<String>] other commands for the same action
        # @param args [Array<String, Symbol>] declared attributes, taken by position
        # @return [Hash]
        # @raise [ArgumentError] for an args entry that is not a declared attribute, or the id
        #   of an action that works on one record
        def cli(command, aliases: [], args: [])
          unknown = args.map(&:to_s) - declared_attributes.keys - (takes_id? ? ["id"] : [])
          raise ArgumentError, "cli args #{unknown.join(", ")} are not attributes of #{action_name}" if unknown.any?
          @declared_cli = {command: command.split, aliases: aliases.map(&:split), args: args.map(&:to_s)}
        end

        # @return [Hash, nil] the command declared with `cli`
        def declared_cli = @declared_cli

        # Declares who may see and run the action by the permission keys
        # they hold (Configuration#permissions_held), or :everyone for every
        # signed-in person. Each requirement is a key, or any_of(...) keys of
        # which one will do. Every requirement must be met. A declared
        # permission takes the place of permitted?'s policy question about
        # the person's role; the policy still decides on each record.
        #
        # @param requirements [Array<String, Symbol, Array<String>>]
        # @return [Array<String, Array<String>>]
        # @raise [ArgumentError] with no requirement
        #
        # @example
        #   permission "events.manage", any_of("comments.update", "comments.delete")
        def permission(*requirements)
          raise ArgumentError, "permission needs a key or :everyone" if requirements.empty?
          return self._permissions = [] if requirements == [:everyone]
          self._permissions = requirements.map { it.is_a?(Array) ? it : it.to_s }
        end

        # @param keys [Array<String, Symbol>] two or more keys
        # @return [Array<String>] one requirement met by holding any of them
        def any_of(*keys)
          raise ArgumentError, "any_of needs two keys or more" if keys.size < 2
          keys.map(&:to_s).freeze
        end

        # @return [Array<String, Array<String>>, nil] the declared requirements, [] for everyone, nil when undeclared
        def permissions = _permissions

        # @return [Array<String>, nil] every key the declaration names
        def permission_keys = permissions&.flatten&.uniq

        # @param held [Array<String>] the keys a person holds
        # @return [Boolean] whether they meet every declared requirement
        def permissions_met?(held) = permissions.all? { Array(it).intersect?(held) }

        # Declares the JSON Schema of the body the action renders, so agents
        # know what comes back and specs can check it (match_output_schema).
        # On a list action with a summary it describes the view screens get;
        # the catalog gives agents summary_output_schema instead.
        #
        # Called with nothing, it returns the declared schema, or nil.
        #
        # @param schema [Hash, nil]
        # @return [Hash, nil]
        def output_schema(schema = nil)
          return @output_schema unless schema
          @output_schema = schema.deep_stringify_keys.freeze
        end

        private

        # Model summaries are keyed by name, so a reloaded model class still finds its own.
        def inherited_summary
          return unless model
          ancestors.each do |ancestor|
            found = ancestor.respond_to?(:model_summaries) && ancestor.model_summaries[model.name]
            return found if found
          end
          nil
        end
      end
    end
  end
end
