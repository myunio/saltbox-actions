module Saltbox
  module Actions
    # Who is calling an action: the person, the surface, the agent acting for
    # them, the token's scopes, the connection and what it may reach. Built by
    # each surface's entry point from its credential, never from anything the
    # caller sends.
    #
    # The app subclasses it to add its own constructors (from an OAuth token,
    # say) and #refresh!.
    #
    # Surfaces, by default:
    # - screen: a person clicking on the app's own screens;
    # - webmcp: a browser assistant on the person's page;
    # - api: a script with a token;
    # - mcp: an AI agent;
    # - assistant: the app's own chat.
    class Caller < Data.define(:account, :surface, :agent, :scopes, :connection, :credential_id, :access)
      # @param account [Object] the person the action acts for
      # @param surface [String] one of Configuration#surfaces
      # @param agent [String, nil] the agent's name, for audit and change notes
      # @param scopes [Array<String>] the token's scopes; a person on a screen holds every scope
      # @param connection [Object, nil] the app connection behind a token
      # @param credential_id [String, nil] the token's id
      # @param access [#allows?, nil] what the connection may reach, beyond the token's scopes;
      #   nil reaches every action
      def initialize(account:, surface:, agent: nil, scopes: nil, connection: nil, credential_id: nil, access: nil)
        raise ArgumentError, "Unknown surface #{surface.inspect}" unless Actions.config.surfaces.include?(surface.to_s)
        scopes ||= Actions.config.scopes.values
        super(account:, surface: surface.to_s, agent:, scopes: scopes.to_a.freeze, connection:, credential_id:, access:)
      end

      # @param account [Object]
      # @param webmcp [Boolean] the page's tool wrapper marked the call as a browser assistant's
      # @return [Caller] a person on a screen
      def self.screen(account, webmcp: false)
        webmcp ? new(account:, surface: "webmcp", agent: "Browser assistant") : new(account:, surface: "screen")
      end

      # @param account [Object]
      # @param agent [String]
      # @return [Caller] the app's chat acting for its person
      def self.assistant(account, agent: "#{Actions.config.app_name} assistant") = new(account:, surface: "assistant", agent:)

      # Decided by the surface, never by the agent's display name.
      # @return [Boolean] whether anything but the person's own click is acting
      def agent? = surface != Actions.config.surfaces.first

      # @param scope [String]
      # @return [Boolean]
      def allows?(scope) = scopes.include?(scope)

      # @param action [Class]
      # @return [Boolean] whether the connection's access reaches the action; always for a caller without one
      def reaches?(action) = access.nil? || access.allows?(action)

      # Whether this caller may run the action, by where the call comes from.
      # The action's policy decides what the person may do; this decides what
      # an agent or script acting for them may do.
      # - A person on a screen may run anything their policy allows.
      # - Every other caller follows the action's `connections` declaration.
      # - The chat assistant never runs a :confirm action. Any other agent may,
      #   unless Configuration#enforce_confirm is on: then Invocation also asks
      #   the app's Configuration#confirm hook.
      # - A browser assistant on the page (WebMCP) never runs a destructive action.
      #
      # @param action [Class]
      # @return [Boolean]
      def agent_allowed?(action)
        return true unless agent?
        return false if action.kind == :destructive && surface == "webmcp"
        case action.connections
        when :allowed then true
        when :confirm then surface != "assistant"
        else false
        end
      end

      # Checks, inside a running action, that this caller may also do what
      # another action does, under its rules: for an action whose input can
      # reach what a stricter action guards, such as a create that can also
      # publish.
      #
      # @example
      #   actor.confirm!(Events::PublishAction) if params[:state] == "published"
      #
      # @param action [Class]
      # @return [void]
      # @raise [Error::HumanRequired] when its `connections` declaration bars this caller
      # @raise [Error::ConfirmationRequired] when it is :confirm, Configuration#enforce_confirm
      #   is on, and the app's Configuration#confirm hook does not approve it
      # @raise [ArgumentError] outside a running action
      def confirm!(action)
        invocation = Current.invocation or raise ArgumentError, "confirm! checks a caller inside a running action"
        raise Error::HumanRequired unless agent_allowed?(action)
        invocation.confirm!(action)
      end

      # The caller as it stands now, reloaded by the app's around_invocation
      # hook so a revoked token or ended access stops the next call.
      #
      # @return [Caller]
      def refresh! = self
    end
  end
end
