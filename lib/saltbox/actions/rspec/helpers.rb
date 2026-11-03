require "saltbox/actions/testing/callers"

module Saltbox
  module Actions
    module RSpec
      # Included in every `type: :action` spec. Each caller helper builds the
      # caller through the app's factory (RSpec.configure); #run sends the
      # input through Invocation, the path every surface takes.
      #
      # @example
      #   it "renames the event" do
      #     result = run({id: event.id, title: "AGM"}, as: as_mcp(manager))
      #     expect(result.body.dig("data", "event", "title")).to eq("AGM")
      #   end
      #
      #   it "is for a person alone" do
      #     expect { run({id: event.id}, as: as_mcp(manager)) }.to be_refused.with(:human_required)
      #   end
      module Helpers
        include Testing::Callers

        private def caller_configuration = RSpec.config

        # Runs the action as the caller.
        #
        # @param arguments [Hash] the input, as a client would send it
        # @param as [Caller]
        # @param action [Class, String] the action, or its name; the described class by default
        # @return [Result]
        # @raise [Error] when the action refuses
        def run(arguments = {}, as:, action: described_class)
          Invocation.call(action: action, caller: as, arguments:)
        end
      end
    end
  end
end
