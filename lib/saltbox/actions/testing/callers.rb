module Saltbox
  module Actions
    module Testing
      # Caller factories run in the test, so fixtures and other helpers work.
      module Callers
        # @param account [Object]
        # @return [Caller] the person on the app's own screens
        def as_screen(account) = caller_configuration.build(:screen, account, example: self)

        # @param account [Object]
        # @return [Caller] a browser assistant on the person's page
        def as_webmcp(account) = caller_configuration.build(:webmcp, account, example: self)

        # @param account [Object]
        # @param scopes [Array<String>, nil] the token's scopes; every scope by default
        # @return [Caller] a script with the person's token
        def as_api(account, scopes: nil) = caller_configuration.build(:api, account, example: self, scopes:)

        # @param account [Object]
        # @param scopes [Array<String>, nil]
        # @return [Caller] an AI agent connected as the person
        def as_mcp(account, scopes: nil) = caller_configuration.build(:mcp, account, example: self, scopes:)

        # @param account [Object]
        # @return [Caller] the app's chat acting for the person
        def as_assistant(account) = caller_configuration.build(:assistant, account, example: self)

        # @param account [Object]
        # @return [Caller] a token that may only read
        def as_read_only(account) = as_api(account, scopes: [Actions.config.scopes.fetch(:read)])
      end
    end
  end
end
