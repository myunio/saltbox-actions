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
        # @param account [Object]
        # @return [Caller] the person on the app's own screens
        def as_screen(account) = RSpec.config.build(:screen, account, example: self)

        # @param account [Object]
        # @return [Caller] a browser assistant on the person's page
        def as_webmcp(account) = RSpec.config.build(:webmcp, account, example: self)

        # @param account [Object]
        # @param scopes [Array<String>, nil] the token's scopes; every scope by default
        # @return [Caller] a script with the person's token
        def as_api(account, scopes: nil) = RSpec.config.build(:api, account, example: self, scopes:)

        # @param account [Object]
        # @param scopes [Array<String>, nil]
        # @return [Caller] an AI agent connected as the person
        def as_mcp(account, scopes: nil) = RSpec.config.build(:mcp, account, example: self, scopes:)

        # @param account [Object]
        # @return [Caller] the app's chat acting for the person
        def as_assistant(account) = RSpec.config.build(:assistant, account, example: self)

        # @param account [Object]
        # @return [Caller] a token that may only read
        def as_read_only(account) = as_api(account, scopes: [Actions.config.scopes.fetch(:read)])

        # Runs the action as the caller.
        #
        # @param arguments [Hash] the input, as a client would send it
        # @param as [Caller]
        # @param action [Class, String] the action, or its name; the described class by default
        # @return [Result]
        # @raise [Error] when the action refuses
        def run(arguments = {}, as:, action: described_class)
          Invocation.call(name: action, caller: as, arguments:)
        end
      end
    end
  end
end
