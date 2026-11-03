module Saltbox
  module Actions
    module Adapters
      module Testing
        # Caller factories run in the test, so fixtures and other helpers work.
        module Callers
          # @param user [Object]
          # @return [Caller] the person on the app's own screens
          def as_screen(user) = caller_configuration.build(:screen, user, example: self)

          # @param user [Object]
          # @return [Caller] a browser assistant on the person's page
          def as_webmcp(user) = caller_configuration.build(:webmcp, user, example: self)

          # @param user [Object]
          # @param scopes [Array<String>, nil] the token's scopes; every scope by default
          # @return [Caller] a script with the person's token
          def as_api(user, scopes: nil) = caller_configuration.build(:api, user, example: self, scopes:)

          # @param user [Object]
          # @param scopes [Array<String>, nil]
          # @return [Caller] an AI agent connected as the person
          def as_mcp(user, scopes: nil) = caller_configuration.build(:mcp, user, example: self, scopes:)

          # @param user [Object]
          # @return [Caller] the app's chat acting for the person
          def as_assistant(user) = caller_configuration.build(:assistant, user, example: self)

          # @param user [Object, nil] who the policy sees; SystemUser when nil
          # @return [Caller] the app itself, in a job, a rake task or the console
          def as_system(user = nil) = caller_configuration.build(:system, user, example: self)

          # @param user [Object]
          # @return [Caller] a token that may only read
          def as_read_only(user) = as_api(user, scopes: [Actions.config.scopes.fetch(:read)])
        end
      end
    end
  end
end
