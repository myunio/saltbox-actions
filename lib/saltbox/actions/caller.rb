require "singleton"

module Saltbox
  module Actions
    # Who is calling an action: the person, the surface, the agent acting for
    # them, the token's scopes, the connection and what it may reach. Built by
    # each surface's entry point from its credential, never from anything the
    # caller sends.
    #
    # The app subclasses it to add its own constructors (from an OAuth token,
    # say) and #refresh.
    #
    # Surfaces, by default:
    # - screen: a person clicking on the app's own screens;
    # - webmcp: a browser assistant on the person's page;
    # - api: a script with a token;
    # - mcp: an AI agent;
    # - assistant: the app's own chat.
    #
    # One more surface is fixed, outside Configuration#surfaces: system, the
    # app itself in a job, a rake task or the console (Caller.system). The
    # API, MCP and the assistant refuse it.
    class Caller < Data.define(:user, :surface, :agent_name, :scopes, :connection, :credential_id, :access)
      # @param user [Object] the person the action acts for
      # @param surface [String] one of Configuration#surfaces, or system
      # @param agent_name [String, nil] the agent's name, for audit and change notes
      # @param scopes [Array<String>] the token's scopes; a person on a screen holds every scope
      # @param connection [Object, nil] the app connection behind a token
      # @param credential_id [String, nil] the token's id
      # @param access [#allows?, nil] what the connection may reach, beyond the token's scopes;
      #   nil reaches every action
      def initialize(user:, surface:, agent_name: nil, scopes: nil, connection: nil, credential_id: nil, access: nil)
        raise ArgumentError, "Unknown surface #{surface.inspect}" unless surface.to_s == SYSTEM || Actions.config.surfaces.include?(surface.to_s)
        scopes ||= Actions.config.scopes.values
        super(user:, surface: surface.to_s, agent_name:, scopes: scopes.to_a.freeze, connection:, credential_id:, access:)
      end

      # @param user [Object]
      # @return [Caller] a person on a screen
      def self.screen(user) = new(user:, surface: "screen")

      # For a call the page's tool wrapper marks as a browser assistant's.
      #
      # @param user [Object]
      # @return [Caller] a browser assistant on the person's page
      def self.webmcp(user) = new(user:, surface: "webmcp", agent_name: "Browser assistant")

      # @param user [Object]
      # @param agent_name [String]
      # @return [Caller] the app's chat acting for its person
      def self.assistant(user, agent_name: "#{Actions.config.app_name} assistant") = new(user:, surface: "assistant", agent_name:)

      # The surface of the app itself, running an action with no request
      # behind it.
      # @api private
      SYSTEM = "system"

      # The app itself, in a job, a rake task or the console. It is not an
      # agent: its `agents` never bar it, it holds every scope, and no
      # one is asked to confirm. Its user still goes through the action's
      # authorization like a person's, so the policy decides what the app may
      # do, and a policy that has no answer for it refuses.
      #
      # The API, MCP and the assistant refuse a system caller: build theirs
      # from the request's credential.
      #
      # @param user [Object] who the policy sees; SystemUser by default,
      #   or a record of the app's own, such as a system user
      # @param agent_name [String, nil] a name for audit and change notes, such as the job's
      # @return [Caller]
      #
      # @example
      #   Events::UpdateAction.perform_now(caller: ApplicationAction::Caller.system, id: 1, title: "AGM")
      def self.system(user = SystemUser.instance, agent_name: nil) = new(user:, surface: SYSTEM, agent_name:)

      # @return [Boolean] whether the app itself is calling (Caller.system)
      def system? = surface == SYSTEM

      # Decided by the surface, never by the agent's display name.
      # @return [Boolean] whether anything but the person's own click, or the app itself, is acting
      def agent? = !system? && surface != Actions.config.surfaces.first

      # @param scope [String]
      # @return [Boolean]
      def includes_scope?(scope) = scopes.include?(scope)

      # @param action [Class]
      # @return [Boolean] whether the connection's access reaches the action; always for a caller without one
      def reaches?(action) = access.nil? || access.allows?(action)

      # Whether this caller may run the action, by where the call comes from.
      # The action's policy decides what the person may do; this decides what
      # an agent or script acting for them may do.
      # - A person on a screen, or the app itself (Caller.system), may run
      #   anything the policy allows.
      # - Every other caller follows the action's `agents` declaration.
      # - The chat assistant never runs a :confirm action. Any other agent may
      #   once the app's Configuration#confirm hook approves, which Invocation
      #   asks while Configuration#enforce_confirm is on (the default).
      # - A browser assistant on the page (WebMCP) never runs a destructive action.
      #
      # @param action [Class]
      # @return [Boolean]
      def agent_allowed?(action)
        return true unless agent?
        return false if action.kind == :destructive && surface == "webmcp"
        case action.agents
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
      #   current_caller.confirm!(Events::PublishAction) if state == "published"
      #
      # @param action [Class]
      # @return [void]
      # @raise [Error::HumanRequired] when its `agents` declaration bars this caller
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
      def refresh = self

      # Refuses a system caller at an entry point that serves requests: its
      # caller comes from the request's credential, never from the app
      # itself.
      #
      # @api private
      # @param caller [Caller]
      # @param entry [String] the entry point, for the message
      # @return [Caller] the caller
      # @raise [ArgumentError] for a system caller
      def self.from_request!(caller, entry)
        return caller unless caller.respond_to?(:system?) && caller.system?
        raise ArgumentError, "#{entry} refuses Caller.system, which is for jobs, rake tasks and the console. Build its caller from the request's credential."
      end
    end

    # The user a system caller (Caller.system) acts as when the app names
    # none. It is not a person, so a policy tells it apart and decides what
    # the app itself may do:
    #
    #   def update? = user.is_a?(Saltbox::Actions::SystemUser) || record.user_id == user.id
    #
    # It has no id, so an audit trail records no person.
    class SystemUser
      include Singleton

      # @return [nil]
      def id = nil

      # @return [String]
      def to_s = "System"

      # @return [String]
      def inspect = "#<#{self.class.name}>"
    end
  end
end
