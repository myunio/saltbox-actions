module Saltbox
  module Actions
    # The settings an action declares at the top of its class, for what its
    # class name cannot give. Naming reads everything else from the name.
    # - `connections` (required, unless Configuration#default_connections is set):
    #   whether agents and scripts may run it.
    # - `action_name`, `title`, `description` (Naming): for an app whose names are already public.
    # - `kind`: read, change or destructive, for a verb not in Naming::VERBS.
    # - `permission`: the permission keys a person needs to see and run it.
    # - `authorize`: the policy rule, when the verb's own is not the right one.
    # - `argument`: an input that is not a field the policy permits.
    # - `idempotent`: calling it again with the same input changes nothing more.
    # - `mcp_core`: list the action as an MCP tool of its own.
    # - `feature`: the feature flag the action needs.
    # - `cli_columns`, or `cli`: the CLI's columns, or its whole command.
    # - `returns`: the JSON Schema of the body it renders.
    module Declarations
      extend ActiveSupport::Concern

      CONNECTIONS = %i[allowed confirm never].freeze
      TYPES = %i[string integer decimal boolean date time array hash].freeze
      # The JSON Schema keywords an argument may add, by their Ruby names.
      KEYWORDS = {format: "format", minimum: "minimum", maximum: "maximum", min_length: "minLength",
                  max_length: "maxLength", pattern: "pattern", default: "default"}.freeze

      class_methods do
        # Whether a caller other than a person on the app's screens may run the
        # action: the CLI, an AI agent over MCP, a script on the API, the chat
        # assistant, or a browser assistant on the page. Every action declares it.
        # - :allowed: they may run it.
        # - :confirm: an agent is told to ask the person first. The chat
        #   assistant never runs it. With Configuration#enforce_confirm on,
        #   the server refuses it until the app's confirm hook approves.
        # - :never: only the person, on a screen.
        #
        # @param rule [Symbol, nil] :allowed, :confirm or :never
        # @return [Symbol, nil]
        def connections(rule = nil)
          return @connections || Actions.config.default_connections unless rule
          raise ArgumentError, "connections is :allowed, :confirm or :never, not #{rule.inspect}" unless CONNECTIONS.include?(rule)
          @connections = rule
        end

        # Declares the kind of an action whose verb is not in VERBS.
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

        # Declares the policy rule authorize asks. An action named with more
        # than a verb, or with a verb outside VERBS, must declare one:
        # Event::ShowAttendeesAction asks view_attendees?.
        #
        # @param query [Symbol]
        # @return [Symbol]
        def authorize(query) = @declared_query = query

        # @return [Symbol, nil] the rule declared with `authorize`
        def declared_query = @declared_query

        # Declares an input that is not a field the policy permits. `argument
        # :id`, with no type, declares the id of the one record the action
        # works on, for a verb outside VERBS.
        #
        # @param name [Symbol]
        # @param type [Symbol, nil] one of TYPES
        # @param required [Boolean]
        # @param nullable [Boolean] whether null clears the value; otherwise null counts as left out
        # @param enum [Array, nil] the allowed values
        # @param of [Symbol, Hash, nil] for an :array, what it holds: a type, or each item's fields and their types
        # @param description [String, nil] the input's description, in place of the locale file's
        # @param keywords [Hash] JSON Schema keywords from KEYWORDS: minimum:, max_length:, default:…;
        #   a default is also the value #perform reads when the caller leaves the input out
        # @return [Hash] {schema:, required:}: the input's JSON Schema, and whether callers must send it
        # @raise [ArgumentError] when an input other than id has no type, or its type is not in TYPES,
        #   or for a keyword not in KEYWORDS
        #
        # @example A list of records, each with typed fields
        #   argument :payments, :array, of: {amount: :decimal, paid_on: :date, meta: :hash}
        # @example A described input with limits
        #   argument :page, :integer, minimum: 1, description: "Page number, from 1"
        def argument(name, type = nil, required: false, nullable: false, enum: nil, of: nil, description: nil, **keywords)
          name = name.to_s
          @input_schema = nil
          return arguments[name] = {schema: Schema::ID, required: true} if name == "id" && type.nil?
          raise ArgumentError, "#{name} takes a type: one of #{TYPES.join(", ")}" unless TYPES.include?(type)
          unknown = keywords.keys - KEYWORDS.keys
          raise ArgumentError, "#{name} takes no #{unknown.join(", ")}: use one of #{KEYWORDS.keys.join(", ")}" if unknown.any?
          schema = Schema.for_argument(type, nullable:, enum:, of:)
          schema = {"type" => schema["type"], "description" => description.squish}.merge(schema) if description
          keywords.each { |key, value| schema[KEYWORDS.fetch(key)] = value.as_json }
          arguments[name] = {schema:, required:}
        end

        # @return [Hash{String => Hash}] declared inputs by name, including the parent class's
        def arguments = @arguments ||= (superclass.respond_to?(:arguments) ? superclass.arguments.dup : {})

        # Declares that calling the action again with the same input changes
        # nothing more than the first call did.
        #
        # @return [void]
        def idempotent = @idempotent = true

        # @return [Boolean] true for a read, except an export, which starts a new export on every call; otherwise only when declared
        def idempotent? = (kind == :read && verb != "export") || @idempotent || false

        # Lists the action as an MCP tool of its own. Other actions are reached
        # through find_action. Keep these to about fifteen.
        #
        # @return [void]
        def mcp_core = @mcp_core = true

        # @return [Boolean] whether the action is an MCP tool of its own
        def mcp_core? = @mcp_core || false

        # The feature flag the action needs. While the flag is off for the
        # caller, every caller gets not_found and the actions list leaves the
        # action out. Configuration#validate_feature checks the key.
        #
        # @param key [String, nil]
        # @return [String, nil]
        def feature(key = nil)
          return @feature unless key
          Actions.config.validate_feature.call(key)
          @feature = key
        end

        # Declares the columns the CLI prints when it shows the action's
        # records as a table. Called with no columns, it returns the declared
        # ones, or an empty array.
        #
        # @param columns [Array<Symbol>] column names, in print order
        # @return [Array<String>]
        def cli_columns(*columns)
          return declared_cli&.fetch(:columns) || @cli_columns || [] if columns.empty?
          @cli_columns = columns.map(&:to_s)
        end

        # Declares the whole CLI command, for an app whose commands are
        # already in use: the words people type, other words for it, the
        # arguments taken by position, and the columns of its table.
        #
        # @param command [String] such as "invoices send"
        # @param aliases [Array<String>] other commands for the same action
        # @param args [Array<String, Symbol>] declared arguments, taken by position
        # @param columns [Array<String, Symbol>]
        # @return [Hash]
        # @raise [ArgumentError] for an args entry that is not a declared argument
        def cli(command, aliases: [], args: [], columns: [])
          unknown = args.map(&:to_s) - arguments.keys
          raise ArgumentError, "cli args #{unknown.join(", ")} are not arguments of #{action_name}" if unknown.any?
          @declared_cli = {command: command.split, aliases: aliases.map(&:split), args: args.map(&:to_s), columns: columns.map(&:to_s)}
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
          return @permissions = [] if requirements == [:everyone]
          @permissions = requirements.map { it.is_a?(Array) ? it : it.to_s }
        end

        # @param keys [Array<String, Symbol>] two or more keys
        # @return [Array<String>] one requirement met by holding any of them
        def any_of(*keys)
          raise ArgumentError, "any_of needs two keys or more" if keys.size < 2
          keys.map(&:to_s).freeze
        end

        # @return [Array<String, Array<String>>, nil] the declared requirements, [] for everyone, nil when undeclared
        def permissions = @permissions

        # @return [Array<String>, nil] every key the declaration names
        def permission_keys = permissions&.flatten&.uniq

        # @param held [Array<String>] the keys a person holds
        # @return [Boolean] whether they meet every declared requirement
        def permissions_met?(held) = permissions.all? { Array(it).intersect?(held) }

        # Declares the JSON Schema of the body the action renders, so agents
        # know what comes back and specs can check it (match_output_schema).
        #
        # @param schema [Hash]
        # @return [Hash]
        def returns(schema) = @output_schema = schema.deep_stringify_keys.freeze

        # @return [Hash, nil] the schema declared with `returns`
        def output_schema = @output_schema
      end
    end
  end
end
