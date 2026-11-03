require "ruby_llm"

module Saltbox
  module Actions
    module Adapters
      module FrontDoors
        # Presents the front door to an in-app chat as RubyLLM tools. Results
        # and refusals come back as JSON marked as record data (see RecordData),
        # so the model can explain the next step without taking orders from a
        # record. Put RecordData::NOTE in the chat's instructions too.
        #
        # @example
        #   chat.with_instructions(Saltbox::Actions::RecordData::NOTE)
        #   chat.with_tools(*Saltbox::Actions::Adapters::FrontDoors::RubyLLMTool.for(ApplicationAction::Caller.assistant(user)))
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
          # @return [String] the action's response body, or the error, as JSON marked as
          #   record data; "Done." when it has none
          def execute(**arguments)
            result = FrontDoor.call(@tool.name, arguments.deep_stringify_keys, caller: @caller)
            result.equal?(FrontDoor::EMPTY) ? "Done." : RecordData.wrap(result)
          rescue Error => error
            RecordData.wrap(error.as_json)
          end
        end
      end
    end
  end
end
