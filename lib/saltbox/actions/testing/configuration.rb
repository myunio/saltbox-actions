module Saltbox
  module Actions
    module Testing
      # How tests build a caller for a person on each surface. Each factory
      # runs inside the example, so it may use the app's fixtures and factories.
      # A surface the app does not set uses the gem's Caller, with the
      # person as its account.
      class Configuration
        AGENT = "Test agent".freeze

        def initialize
          @factories = {}
        end

        # @param surface [Symbol] :screen, :webmcp, :api, :mcp or :assistant
        # @yieldparam account [Object] the person
        # @yieldparam scopes [Array<String>] the token's scopes, for :api and :mcp
        # @yieldreturn [Caller]
        # @return [void]
        def caller_for(surface, &block) = @factories[surface.to_sym] = block

        # @param surface [Symbol]
        # @param account [Object]
        # @param example [Object] the running example, which the factory runs in
        # @param scopes [Array<String>, nil]
        # @return [Caller]
        def build(surface, account, example:, scopes: nil)
          factory = @factories[surface]
          return example.instance_exec(account, **({scopes: scopes || Actions.config.scopes.values} if token?(surface)).to_h, &factory) if factory
          default(surface, account, scopes:)
        end

        private

        def token?(surface) = %i[api mcp].include?(surface)

        def default(surface, account, scopes:)
          caller_class = Actions.config.base.const_get(:Caller)
          case surface
          when :screen then caller_class.screen(account)
          when :webmcp then caller_class.screen(account, webmcp: true)
          when :assistant then caller_class.assistant(account)
          else caller_class.new(account:, surface: surface.to_s, agent: self.class::AGENT, scopes: scopes || Actions.config.scopes.values)
          end
        end
      end
    end
  end
end
