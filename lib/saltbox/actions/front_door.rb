module Saltbox
  module Actions
    # The tools agents see, free of any protocol, shared by the MCP adapter
    # and the assistant tools: the `mcp_core` actions as tools of their own,
    # find_action to search the rest, and one run tool per kind.
    module FrontDoor
      # A tool as MCP clients and assistants see it: its name, title,
      # description, input schema and behavior hints (read-only, destructive,
      # idempotent).
      Tool = Data.define(:name, :title, :description, :input_schema, :annotations)
      FIND = "find_action".freeze
      RUN = {read: "run_read_action", change: "run_change_action", destructive: "run_destructive_action"}.freeze
      RUN_TEXT = {
        read: ["Look something up in %{app}",
          "Use this when find_action has found a read action for the person's request. Runs it by name with its arguments and returns its result. Changes nothing."],
        change: ["Make a change in %{app}",
          "Use this when find_action has found a change action for the person's request. Runs it by name with its arguments and returns its result. Say what will change and get a yes first."],
        destructive: ["Remove something in %{app}",
          "Use this when find_action has found an action that removes something or cannot be undone. Runs it by name with its arguments and returns its result. Say exactly what will be removed and get a yes first."]
      }.freeze

      # The tools this caller gets, in order:
      # - each action they may run that is declared `mcp_core`, as a tool of its own;
      # - find_action, to search the other actions;
      # - one run tool (run_read_action, run_change_action or run_destructive_action)
      #   for each kind of action they may run.
      #
      # @param caller [Caller]
      # @return [Array<Tool>]
      def self.tools(caller)
        runnable = Registry.runnable(caller)
        direct = runnable.select(&:mcp_core?).map do |action|
          Tool.new(name: action.action_name, title: action.title, description: [action.description, action.summary_note].compact.join(" ").presence,
            input_schema: action.input_schema, annotations: annotations(action.kind, idempotent: action.idempotent?))
        end
        direct + [find_tool] + RUN.keys.select { |kind| runnable.any? { |action| action.kind == kind } }.map { |kind| run_tool(kind) }
      end

      # @param tool_name [String]
      # @param arguments [Hash]
      # @param caller [Caller]
      # @return [Object] the action's response: any JSON value, false and nil included, or EMPTY
      #   when it has no body (head); or find_action's matches
      # @raise [Error] when the action is unknown, the caller may not run it, or the input is invalid;
      #   every other surface gets the same errors in those cases
      def self.call(tool_name, arguments, caller:)
        if tool_name == FIND
          query = Arguments.new(find_tool.input_schema).validate!(arguments).fetch("query")
          return find(query, caller)
        end
        if (kind = RUN.key(tool_name))
          name, action_arguments = run_wrapper!(arguments)
          return response(Invocation.call(name: name, caller: caller, arguments: action_arguments, expected_kind: kind))
        end
        action = Registry.fetch(tool_name)
        raise Error::UnknownAction, tool_name unless action.mcp_core?
        response(Invocation.call(name: action, caller: caller, arguments: arguments))
      end

      # What FrontDoor.call returns for a response with no body, which each
      # tool adapter reports as "Done.". A JSON null is a body.
      EMPTY = Object.new.freeze

      # @param result [Result]
      # @return [Object] its JSON, or EMPTY
      def self.response(result) = result.empty? ? EMPTY : result.as_json

      # Checks only a run tool's own wrapper: Invocation admits the caller
      # before it checks the action's arguments, including their type.
      #
      # @param wrapper [Hash, nil] the run tool's arguments
      # @return [Array(String, Object)] the action's name and its arguments, unchecked
      # @raise [Error::Invalid] for a wrapper that is not an object, has no name or has other keys
      def self.run_wrapper!(wrapper)
        wrapper = {} if wrapper.nil?
        raise Error::Invalid.new("Arguments must be an object", errors: {"arguments" => ["Must be an object"]}) unless wrapper.is_a?(Hash)
        wrapper = wrapper.stringify_keys
        errors = (wrapper.keys - %w[name arguments]).index_with { ["is not an argument of a run tool"] }
        name = wrapper["name"]
        errors["name"] = ["must be an action's name from find_action"] unless name.is_a?(String) && name.length.between?(1, 64)
        raise Error::Invalid.new(errors.map { |key, messages| "#{key} #{messages.first}" }.join("; "), errors: errors) if errors.any?
        [name, wrapper["arguments"]]
      end

      # @param kind [Symbol]
      # @param idempotent [Boolean]
      # @return [Hash] advisory protocol-independent behavior hints
      def self.annotations(kind, idempotent:)
        {read_only_hint: kind == :read, destructive_hint: kind == :destructive, idempotent_hint: idempotent, open_world_hint: false}
      end

      # @return [Tool] the plain-words discovery contract
      def self.find_tool
        Tool.new(name: FIND, title: "Find something to do in #{app}",
          description: "Use this when none of the listed tools covers the person's request. Describe it in plain words. Returns matching actions, their arguments and which run tool to use.",
          input_schema: {"type" => "object", "properties" => {"query" => {"type" => "string", "minLength" => 1, "maxLength" => 200, "description" => "The request in plain words"}}, "required" => ["query"], "additionalProperties" => false},
          annotations: annotations(:read, idempotent: true))
      end

      # @param kind [Symbol]
      # @return [Tool] a typed named-execution contract
      def self.run_tool(kind)
        title, description = RUN_TEXT.fetch(kind)
        Tool.new(name: RUN.fetch(kind), title: format(title, app:), description: description,
          input_schema: {"type" => "object", "properties" => {
            "name" => {"type" => "string", "minLength" => 1, "maxLength" => 64, "description" => "The action's name from find_action"},
            "arguments" => {"type" => %w[object null], "description" => "The action's arguments"}
          }, "required" => ["name"], "additionalProperties" => false}, annotations: annotations(kind, idempotent: kind == :read))
      end

      # @param query [String]
      # @param caller [Caller]
      # @return [Hash] visible matches with separate execution eligibility
      def self.find(query, caller)
        Actions.within(caller) do |fresh|
          available = Registry.actions.select { |action| action.available_to?(fresh) }
          actions = Finder.new(available).find(query).map do |action|
            runnable = action.runnable_for?(fresh)
            {name: action.action_name, title: action.title, description: action.description, arguments: action.input_schema,
             returns: action.summary_note, run_with: runnable ? RUN.fetch(action.kind) : nil, confirm_first: action.connections == :confirm,
             message: ("Only a person can do this, in #{app}" unless runnable)}.reject { |key, value| %i[returns message].include?(key) && value.nil? }
          end
          result = {actions: actions}
          result[:hint] = "Nothing matched. Try other words for the same request." if actions.empty?
          result
        end
      end

      def self.app = Actions.config.app_name
      private_class_method :app
    end
  end
end
