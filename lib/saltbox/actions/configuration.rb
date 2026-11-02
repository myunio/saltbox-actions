module Saltbox
  module Actions
    # What the app decides, set once in config/initializers/actions.rb. Every
    # setting has a default that works for a plain Rails app, so an app sets
    # only what differs.
    #
    # Hooks that wrap work take the work as a callable: call it, inside
    # whatever the app sets up, and return its value.
    #
    # @example
    #   Saltbox::Actions.configure do |config|
    #     config.app_name = "Acme"
    #     config.around_invocation { |caller, run| Context.within(caller) { |fresh| run.(fresh) } }
    #     config.around_run { |invocation, run| PaperTrail.request(whodunnit: invocation.caller.account.id) { run.() } }
    #     config.on_changes { |changes, invocation| publish(changes, invocation) }
    #     config.map_error(MyApp::DomainError) { |error| Saltbox::Actions::Error::Invalid.new(error.message) }
    #   end
    class Configuration
      SCOPES = {read: "api:read", write: "api:write"}.freeze
      SURFACES = %w[screen webmcp api mcp assistant].freeze

      # @return [String] the app's name in tool titles, agent instructions and default error messages
      attr_accessor :app_name
      # @return [String] the app's base action class, whose subclasses under actions_path are its actions
      attr_accessor :base_class
      # @return [String] where the actions live, relative to Rails.root
      attr_accessor :actions_path
      # @return [String] the committed catalogue every action is written to, relative to Rails.root
      attr_accessor :catalogue_path
      # @return [String] the class whose renderer draws action views; a controller's name, read when first used
      attr_accessor :renderer
      # @return [Hash{Symbol => String}] the token scope a read needs and the one anything else needs
      attr_accessor :scopes
      # @return [Array<String>] the surfaces a Caller may come from; the first is a person on a screen
      attr_accessor :surfaces
      # @return [String, nil] the MCP server's instructions to agents
      attr_accessor :instructions
      # @return [Boolean] whether every action's model must belong to an area (see #area_for)
      attr_accessor :require_area
      # @return [Integer, #call] the most items an array argument takes
      attr_writer :max_array_items
      # @return [Symbol, nil] the connections rule of an action that declares none;
      #   nil makes every action declare one
      attr_accessor :default_connections
      # @return [Boolean] whether Invocation refuses a person who lacks an action's
      #   declared permissions; when false they only decide the actions list
      attr_accessor :enforce_permissions
      # @return [Boolean] whether Invocation refuses an agent a :confirm action
      #   unless the #confirm hook approves it; when false, agents on the API,
      #   MCP and a browser page run :confirm actions with nothing checked
      attr_accessor :enforce_confirm
      # @return [Boolean] whether every file under actions_path is an action ending _action.rb;
      #   when false, the actions are the base class's subclasses there, beside other files
      attr_accessor :every_file_an_action
      # @return [Symbol] the error body: :code ({error: {code, message, errors, details}})
      #   or :type ({error: {type, message, details}}), see Error#as_json
      attr_accessor :error_format
      # @return [Symbol] the result body: :body (the rendered body) or :envelope ({data, meta}), see Result#as_json
      attr_accessor :result_format

      def initialize
        @app_name = "the app"
        @base_class = "ApplicationAction"
        @actions_path = "app/actions"
        @catalogue_path = "config/actions.json"
        @renderer = "ApplicationController"
        @scopes = SCOPES
        @surfaces = SURFACES
        @instructions = nil
        @require_area = false
        @max_array_items = 100
        @default_connections = nil
        @enforce_permissions = true
        @enforce_confirm = false
        @every_file_an_action = true
        @error_format = :code
        @result_format = :body
        @permissions_held = ->(_caller) { [] }
        @around_invocation = ->(caller, run) { run.call(caller) }
        @around_run = ->(_invocation, run) { run.call }
        @on_changes = ->(_changes, _invocation) {}
        @after_change = ->(_invocation, _result) {}
        @confirm = ->(_invocation, _action) { false }
        @on_access_refused = ->(_caller, _action) { Error::InsufficientScope.new }
        @feature_enabled = ->(_key, _caller) { true }
        @validate_feature = ->(_key) {}
        @area_for = ->(_model) {}
        @schema_principal = nil
        @error_mappings = []
        @action_checks = []
        @registry_checks = []
      end

      # @return [Class] the base action class
      def base = base_class.constantize

      # @return [Class] the renderer's class
      def renderer_class = renderer.is_a?(String) ? renderer.constantize : renderer

      # @return [Integer]
      def max_array_items = @max_array_items.respond_to?(:call) ? @max_array_items.call : @max_array_items

      # The set-up each invocation, catalogue listing and search runs inside:
      # tenant, time zone, a fresh copy of the caller from the database.
      # The block calls run with the caller it refreshed.
      #
      # @yieldparam caller [Caller]
      # @yieldparam run [Proc] takes the fresh caller
      def around_invocation(&block) = block ? @around_invocation = block : @around_invocation

      # Wraps each action's work, inside the invocation's set-up and outside
      # its transaction: the place for an audit trail's request info.
      #
      # @yieldparam invocation [Invocation]
      # @yieldparam run [Proc]
      def around_run(&block) = block ? @around_run = block : @around_run

      # Receives every record a change changed, inside the change's
      # transaction, so an event stored in the same database commits with it.
      #
      # @yieldparam changes [Array<Array(String, String, String)>] each record's type, id and event
      # @yieldparam invocation [Invocation]
      def on_changes(&block) = block ? @on_changes = block : @on_changes

      # Runs after a change commits, with its result: once every enclosing
      # transaction has committed, and never when one rolls back. It may run
      # after the invocation and the caller's own request context have
      # ended (Current, around_invocation's and around_run's set-up), so it
      # sets up any context it needs itself; invocation.invocation_id and
      # invocation.caller stay readable.
      #
      # @yieldparam invocation [Invocation]
      # @yieldparam result [Result]
      def after_change(&block) = block ? @after_change = block : @after_change

      # Called when a caller's access (Caller#access) does not reach the
      # action. Returns the Error to raise; the place to note the refusal
      # or ask the person.
      #
      # @yieldparam caller [Caller]
      # @yieldparam action [Class]
      # @yieldreturn [Error]
      def on_access_refused(&block) = block ? @on_access_refused = block : @on_access_refused

      # Approves a :confirm action for an agent, when #enforce_confirm is on:
      # the place to ask the person through the app's own channel. Return
      # true to run it; anything else refuses with confirmation_required.
      # Raise an Error to refuse in your own words. Called after every other
      # check and the input's, outside the change's transaction; called from
      # Caller#confirm! inside it.
      #
      # @yieldparam invocation [Invocation] the call: its action, caller and arguments
      # @yieldparam action [Class] the :confirm action to approve; the
      #   invocation's own, or the one Caller#confirm! names
      # @yieldreturn [Boolean]
      def confirm(&block) = block ? @confirm = block : @confirm

      # Whether a feature flag an action declares is on for this caller.
      #
      # @yieldparam key [String]
      # @yieldparam caller [Caller]
      def feature_enabled(&block) = block ? @feature_enabled = block : @feature_enabled

      # The permission keys a caller's person holds, for actions that declare
      # `permission`.
      #
      # @yieldparam caller [Caller]
      # @yieldreturn [Array<String>]
      def permissions_held(&block) = block ? @permissions_held = block : @permissions_held

      # Checks a declared feature key when the action loads; raise to refuse it.
      #
      # @yieldparam key [String]
      def validate_feature(&block) = block ? @validate_feature = block : @validate_feature

      # The area an action's model belongs to, such as "events".
      #
      # @yieldparam model [Class]
      # @yieldreturn [String, nil]
      def area_for(&block) = block ? @area_for = block : @area_for

      # Who the input schema is built for: a principal holding every
      # permission, so every caller sees the same schema. The block calls run
      # with that principal, inside whatever context the policy needs.
      #
      # @yieldparam run [Proc] takes the principal
      def schema_principal(&block) = block ? @schema_principal = block : @schema_principal

      # Turns an app error raised inside an action into an Error callers
      # see. Checked in the order given, before the gem's own mappings, so an
      # app may report an ActiveRecord error its own way, or pass it through.
      #
      # @param error_class [Class<Exception>, String] the class, or its name when it is an
      #   app constant the initializer must not load
      # @yieldparam error [Exception]
      # @yieldreturn [Error, nil] nil re-raises the original
      # @return [void]
      def map_error(error_class, &block) = @error_mappings << [error_class, block]

      # @return [Array<Array(Class, Proc)>]
      attr_reader :error_mappings

      # Adds a boot check for each action, beside the gem's own.
      #
      # @yieldparam action [Class]
      # @yieldreturn [Array<String>] each problem and its fix
      # @return [void]
      def check_action(&block) = @action_checks << block

      # @return [Array<Proc>]
      attr_reader :action_checks

      # Adds a boot check over every action at once, run first.
      #
      # @yieldparam actions [Array<Class>]
      # @return [void]
      def check_registry(&block) = @registry_checks << block

      # @return [Array<Proc>]
      attr_reader :registry_checks

      # @return [String] the scope an action of this kind needs
      def scope_for(kind) = (kind == :read) ? scopes.fetch(:read) : scopes.fetch(:write)
    end
  end
end
