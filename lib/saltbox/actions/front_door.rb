module Saltbox
  module Actions
    # The tools agents see, free of any protocol, shared by the MCP adapter
    # and the assistant tools: the `featured` actions as tools of their own,
    # find_action to search the rest, and one run tool per kind.
    module FrontDoor
      # A tool as MCP clients and assistants see it: its name, title,
      # description, input schema and behavior hints (read-only, destructive,
      # idempotent).
      Tool = Data.define(:name, :title, :description, :input_schema, :annotations)
      FIND = "find_action".freeze
      # How many actions find_action lists on one page when there is no query, and the most it takes.
      PAGE_SIZE = 50
      # Named when a system caller is refused; MCP and the assistant both come through here.
      ENTRY = "MCP and the assistant".freeze
      MAX_PAGE_SIZE = 100
      RUN = {read: "run_read_action", change: "run_change_action", destructive: "run_destructive_action"}.freeze
      RUN_TEXT = {
        read: ["Look something up in %{app}",
          "Use this when find_action has found a read action for the person's request. Runs it by name with its arguments and returns its result. Changes nothing."],
        change: ["Make a change in %{app}",
          "Use this when find_action has found a change action for the person's request. Runs it by name with its arguments and returns its result. When find_action marks it confirm_first, say what will change and get a yes first; otherwise say what you are changing and go ahead."],
        destructive: ["Remove something in %{app}",
          "Use this when find_action has found an action that removes something or cannot be undone. Runs it by name with its arguments and returns its result. Say exactly what will be removed and get a yes first."]
      }.freeze

      # The tools this caller gets, in order:
      # - each action they may run that is declared `featured`, as a tool of its own;
      # - find_action, to search the other actions;
      # - one run tool (run_read_action, run_change_action or run_destructive_action)
      #   for each kind of action they may run.
      #
      # @param caller [Caller] never Caller.system
      # @return [Array<Tool>]
      # @raise [ArgumentError] for a system caller
      def self.tools(caller)
        Caller.from_request!(caller, ENTRY)
        # Inside the caller's set-up, which a policy may need to build each schema.
        Actions.within(caller) do |fresh|
          runnable = Registry.actions.select { |action| action.runnable_for?(fresh) }
          direct = runnable.select(&:featured?).map do |action|
            Tool.new(name: action.action_name, title: action.title, description: [action.description, action.summary_note].compact.join(" ").presence,
              input_schema: action.input_schema(fresh), annotations: annotations(action.kind, idempotent: action.idempotent?))
          end
          direct + [find_tool] + RUN.keys.select { |kind| runnable.any? { |action| action.kind == kind } }.map { |kind| run_tool(kind) }
        end
      end

      # @param tool_name [String]
      # @param arguments [Hash]
      # @param caller [Caller]
      # @return [Object] the action's response: any JSON value, false and nil included, or EMPTY
      #   when it has no body (head); or find_action's matches, or its list when there is no query
      # @raise [Error] when the action is unknown, the caller may not run it, or the input is invalid;
      #   every other surface gets the same errors in those cases
      # @raise [ArgumentError] for a system caller
      def self.call(tool_name, arguments, caller:)
        Caller.from_request!(caller, ENTRY)
        if tool_name == FIND
          arguments = Arguments.new(find_tool.input_schema).validate!(arguments)
          return list(caller, page: arguments.fetch("page", 1), page_size: arguments.fetch("page_size", PAGE_SIZE)) unless arguments.key?("query")
          paging = arguments.keys & %w[page page_size]
          raise Error::Invalid.new("page and page_size list actions only with no query", errors: paging.index_with { ["is only for find_action with no query"] }) if paging.any?
          return find(arguments.fetch("query"), caller)
        end
        if (kind = RUN.key(tool_name))
          name, action_arguments = run_wrapper!(arguments)
          return response(Invocation.call(name: name, caller: caller, arguments: action_arguments, expected_kind: kind))
        end
        action = Registry.fetch(tool_name)
        raise Error::UnknownAction, tool_name unless action.featured?
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
          description: "Use this when none of the listed tools covers the person's request. Describe it in plain words, or name an action. Returns matching actions, their arguments and which run tool to use. Leave query out to list everything you can run, a page at a time, without arguments. #{RecordData::NOTE}",
          input_schema: {"type" => "object", "properties" => {
            "query" => {"type" => "string", "minLength" => 1, "maxLength" => 200, "description" => "The request in plain words, or an action's name"},
            "page" => {"type" => "integer", "minimum" => 1, "description" => "With no query: the page of the list, from 1"},
            "page_size" => {"type" => "integer", "minimum" => 1, "maximum" => MAX_PAGE_SIZE, "description" => "With no query: actions per page, #{PAGE_SIZE} unless set"}
          }, "additionalProperties" => false},
          annotations: annotations(:read, idempotent: true))
      end

      # @param kind [Symbol]
      # @return [Tool] a typed named-execution contract
      def self.run_tool(kind)
        title, description = RUN_TEXT.fetch(kind)
        Tool.new(name: RUN.fetch(kind), title: format(title, app:), description: "#{description} #{RecordData::NOTE}",
          input_schema: {"type" => "object", "properties" => {
            "name" => {"type" => "string", "minLength" => 1, "maxLength" => 64, "description" => "The action's name from find_action"},
            "arguments" => {"type" => %w[object null], "description" => "The action's arguments"}
          }, "required" => ["name"], "additionalProperties" => false}, annotations: annotations(kind, idempotent: kind == :read))
      end

      # @param query [String]
      # @param caller [Caller]
      # @return [Hash] visible matches with separate execution eligibility,
      #   or a hint when nothing matched
      def self.find(query, caller)
        Actions.within(caller) do |fresh|
          available = Registry.actions.select { |action| action.available_to?(fresh) }
          actions = Finder.new(available).find(query).map do |action|
            entry(action, fresh).merge(description: action.description, arguments: action.input_schema(fresh),
              response_description: action.summary_note).reject { |key, value| key == :response_description && value.nil? }
          end
          result = {actions: actions}
          result[:hint] = no_match_hint(available) if actions.empty?
          result
        end
      end

      # Everything this caller can run from here, a page at a time, without
      # descriptions or arguments: find_action with an action's name gives
      # those. Actions only a person may run are left out.
      #
      # @param caller [Caller]
      # @param page [Integer] from 1
      # @param page_size [Integer]
      # @return [Hash] one page of actions, sorted by area (see Configuration#area_order) then name,
      #   with paging meta and a hint naming the next page when there is one
      def self.list(caller, page:, page_size:)
        Actions.within(caller) do |fresh|
          runnable = sorted(Registry.actions.select { |action| action.runnable_for?(fresh) })
          actions = runnable.drop((page - 1) * page_size).first(page_size).map do |action|
            entry(action, fresh).merge(kind: action.kind.to_s, area: action.area).reject { |key, value| key == :area && value.nil? }
          end
          next_page = page + 1 if page * page_size < runnable.size
          hint = "Call find_action with an action's name for what it does and the arguments it takes."
          hint += " Call find_action with page: #{next_page}, page_size: #{page_size} for more." if next_page
          {actions: actions, meta: {page:, page_size:, total: runnable.size, next_page:}, hint: hint}
        end
      end

      # @param action [Class]
      # @param caller [Caller] already refreshed
      # @return [Hash] its name, title, run tool (nil when only a person may run it), confirm_first
      #   and, when only a person may run it, a message saying so
      def self.entry(action, caller)
        runnable = action.runnable_for?(caller)
        {name: action.action_name, title: action.title, run_with: runnable ? RUN.fetch(action.kind) : nil,
         confirm_first: action.connections == :confirm, message: ("Only a person can do this, in #{app}" unless runnable)}
          .reject { |key, value| key == :message && value.nil? }
      end

      # @param actions [Array<Class>]
      # @return [Array<Class>] by area, the areas in Configuration#area_order first and the rest
      #   alphabetically, then those with no area; within each, by name
      def self.sorted(actions)
        order = Actions.config.area_order.map(&:to_s)
        actions.sort_by do |action|
          area = action.area&.to_s
          rank = if area.nil? then [2, 0, ""]
          elsif order.include?(area) then [0, order.index(area), ""]
          else [1, 0, area]
          end
          rank + [action.action_name]
        end
      end

      # @param available [Array<Class>] the actions the caller may see
      # @return [String] what to try when nothing matched, naming the caller's areas when actions have them
      def self.no_match_hint(available)
        areas = sorted(available).filter_map(&:area).map(&:to_s).uniq
        covers = " You can reach #{areas.to_sentence(last_word_connector: " and ")}." if areas.any?
        "Nothing matched. Try other words, or #{app} may not do this yet.#{covers} Call find_action with no query to list everything you can run."
      end

      def self.app = Actions.config.app_name
      private_class_method :app, :entry, :sorted, :no_match_hint
    end
  end
end
