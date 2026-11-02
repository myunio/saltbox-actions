require "ruby_llm"

module Saltbox
  module Actions
    # Presents the front door to an in-app chat as RubyLLM tools. Refusals
    # come back as the error's JSON, so the model can explain the next step.
    #
    # @example
    #   chat.with_tools(*Saltbox::Actions::RubyLLMTool.for(ApplicationAction::Caller.assistant(account)))
    class RubyLLMTool < ::RubyLLM::Tool
      # @param caller [Caller] usually an assistant caller
      # @return [Array<RubyLLMTool>] the tools that caller may run now
      def self.for(caller)
        FrontDoor.tools(caller).map { |tool| new(tool, caller) }
      end

      # @param tool [FrontDoor::Tool]
      # @param caller [Caller] kept for the chat, and refreshed on each call
      def initialize(tool, caller)
        @tool = tool
        @caller = caller
        super()
      end

      # @return [String]
      def name = @tool.name

      # @return [String]
      def description = @tool.description

      # @return [Hash] the tool's input schema
      def parameters_schema = @tool.input_schema

      # @param arguments [Hash] the model's arguments
      # @return [Hash, String] the action's response body: an object as it is, any other JSON
      #   value as its JSON text ("false", "null"); "Done." when it has none; or the error as JSON
      def execute(**arguments)
        result = FrontDoor.call(@tool.name, arguments.deep_stringify_keys, caller: @caller)
        return "Done." if result.equal?(FrontDoor::EMPTY)
        result.is_a?(Hash) ? result : JSON.generate(result)
      rescue Error => error
        error.as_json
      end
    end
  end
end
