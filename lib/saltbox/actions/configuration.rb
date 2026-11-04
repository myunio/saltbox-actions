module Saltbox
  module Actions
    # The app's settings, set once in config/initializers/saltbox_actions.rb.
    # Every setting is a value: a string, symbol, number, boolean, or an
    # array or hash of those. Every one has a default that works for a plain
    # Rails app, so an app sets only what differs.
    #
    # What an app adds to every call (who the caller is now, its tenant and
    # time zone, how an error reaches the caller, what runs once a change
    # commits) is ordinary code in its ApplicationAction: callbacks,
    # rescue_from and a few methods the gem calls, as an ApplicationController
    # holds a request's (see Callbacks).
    #
    # @example
    #   Saltbox::Actions.configure do |config|
    #     config.adapters = [:pundit, :acts_as_tenant, :controller, :mcp, :paper_trail]
    #     config.app_name = "Acme"
    #   end
    class Configuration
      # @api private
      SCOPES = {read: "api:read", write: "api:write"}.freeze
      # @api private
      SURFACES = %w[screen webmcp api mcp assistant].freeze

      # @return [String] the app's name in tool titles, agent instructions and default error messages
      attr_accessor :app_name
      # @return [String] the app's base action class, whose subclasses in action_paths are its actions
      attr_accessor :base_class
      # @return [ActionPaths] the folders actions load from: app/actions, then any an engine adds
      attr_reader :action_paths
      # @return [String] the committed catalog every action is written to, relative to Rails.root
      attr_accessor :catalog_path
      # @return [String] the class whose renderer draws action views; a controller's name, read when first used
      attr_accessor :renderer
      # @return [Hash{Symbol => String}] the token scope a read needs and the one anything else needs
      attr_accessor :scopes
      # @return [Array<String>] the surfaces a Caller may come from; the first is a person on a screen
      attr_accessor :surfaces
      # @return [String, nil] the MCP server's instructions to agents
      attr_accessor :instructions
      # @return [Boolean] whether every action's model must belong to an area (see #areas)
      attr_accessor :require_area
      # @return [Array<String>] the areas find_action lists first, in this order;
      #   the rest follow alphabetically, then actions with no area
      attr_accessor :area_order
      # @return [Array<String>] the models that are lookup lists: short lists
      #   anyone who can pick from them may name by id or by name, such as
      #   event types; a reference to one skips the policy scope (see Base#resolve_reference)
      attr_reader :lookup_lists
      # @return [Integer] page_size when a paginated list's caller leaves it out:
      #   Pagy's limit under the :pagy adapter, else 25
      attr_writer :page_size
      # @return [Integer] the largest page_size a paginated list's caller may ask for:
      #   Pagy's client_limit under the :pagy adapter (100 when it is unset), else 100
      attr_writer :max_page_size
      # @return [Object, nil] what lists page and tables query with (see #list_adapter=)
      attr_reader :list_adapter
      # @return [Integer] the most items an array attribute takes
      attr_reader :max_array_items
      # @return [Boolean] whether Invocation refuses a person who lacks an action's
      #   declared permissions; when false they only decide the actions list
      attr_accessor :enforce_permissions
      # @return [Boolean] whether Invocation refuses an agent a :confirm action
      #   until the person approves it (true by default): with the :approvals
      #   adapter, once they approve that exact call; without it, always. Set
      #   false on purpose to let agents on the API, MCP and a browser page run
      #   :confirm actions with nothing checked
      attr_accessor :enforce_confirm
      # @return [Boolean] whether every Ruby file under action_paths must define an action, in a
      #   file ending _action.rb (true by default); when false, the folders may hold other files
      #   too. Either way the actions are the base class's subclasses there (Registry.descendants):
      #   it checks what the folders hold, nothing more.
      attr_accessor :strict_action_paths
      # @return [Symbol] the error body: :code ({error: {code, message, errors, details}})
      #   or :type ({error: {type, message, details}}), see Error#as_json
      attr_accessor :error_format
      # @return [Symbol] the result body: :body (the rendered body) or :envelope ({data, meta}), see Result#as_json
      attr_accessor :result_format

      # @return [Array<Symbol>] the optional adapters the app switched on (see Adapters);
      #   none by default
      attr_reader :adapters

      def initialize
        @adapters = [].freeze
        @app_name = "the app"
        @base_class = "ApplicationAction"
        @action_paths = ActionPaths.new(["app/actions"])
        @catalog_path = "config/actions.json"
        @renderer = "ApplicationController"
        @scopes = SCOPES
        @surfaces = SURFACES
        @instructions = nil
        @require_area = false
        @area_order = []
        @max_array_items = 100
        @enforce_permissions = true
        @enforce_confirm = true
        @strict_action_paths = true
        @error_format = :code
        @result_format = :body
        @approvals = {user: "User"}.freeze
        @areas = {}.freeze
        @lookup_lists = [].freeze
        @page_size = nil
        @max_page_size = nil
        @list_adapter = nil
      end

      # Declares the optional adapters, the one switch for each: only these
      # load. Checked now, at boot; see Adapters. A declared authorization
      # adapter is included in Base, so every action has it.
      #
      # @param names [Array<Symbol>] such as [:pundit, :mcp, :paper_trail]
      # @raise [ArgumentError, Adapters::MissingGem] naming the fix
      def adapters=(names)
        @adapters = Adapters.declare(names)
        Adapters.authorize_base! if equal?(Actions.config)
      end

      # @param paths [Enumerable<String, Pathname>] the folders actions load from, replacing the list
      def action_paths=(paths)
        @action_paths = ActionPaths.new(paths)
      end

      # @return [Class] the base action class
      # @api private
      def base = base_class.constantize

      # @return [Class] the renderer's class
      # @api private
      def renderer_class = renderer.is_a?(String) ? renderer.constantize : renderer

      # @param count [Integer] the most items an array attribute takes, read when each schema is built
      # @raise [ArgumentError] for anything but a positive whole number
      def max_array_items=(count)
        raise ArgumentError, "config.max_array_items takes a number, such as 100, not #{count.inspect}" unless count.is_a?(Integer) && count.positive?
        @max_array_items = count
      end

      # @return [Integer]
      def page_size = @page_size || (Adapters.declared?(:pagy) ? Adapters::Lists::Pagy.page_size : 25)

      # @return [Integer]
      def max_page_size = @max_page_size || (Adapters.declared?(:pagy) ? Adapters::Lists::Pagy.max_page_size : 100)

      # The app's classes the :approvals adapter's Approval belongs to, by
      # name: the person (user, the caller's user), and optionally the
      # tenant each approval is kept in, acts_as_tenant's current one, and
      # the connection the caller came through. Until the person approves,
      # the agent is told the app's actions.errors.approval_needed, with
      # %{user} (the person, named by their name method, to_s by default),
      # %{app} and %{url} (where they approve).
      #
      # @return [Hash{Symbol=>String, Symbol}]
      #
      # @example
      #   config.approvals = {user: "Account", name: :full_name, tenant: "Org", connection: "Oauth::Connection",
      #     url: "https://app.example.com/settings/connections"}
      attr_reader :approvals

      # @param settings [Hash]
      # @raise [ArgumentError] for an unknown key, or no user
      def approvals=(settings)
        settings = settings.to_h.symbolize_keys
        unknown = settings.keys - %i[user name tenant connection url]
        raise ArgumentError, "config.approvals takes user, name, tenant, connection and url, not #{unknown.join(", ")}" if unknown.any?
        raise ArgumentError, "config.approvals names the person's class as user:" unless settings[:user]
        @approvals = settings.freeze
      end

      # Each area and its models, by name, in the order the app lists its
      # areas (see Areas): every model an action changes belongs to exactly
      # one. An area's rule may also name its metadata_models, the models
      # whose record, person and agent everyone who may read the area may
      # see in a change announcement, and its read_action, the read action
      # that admits a person to the area.
      #
      # @return [Hash{String=>Hash}]
      #
      # @example
      #   config.areas = {
      #     "events" => {models: %w[Event Event::Type], metadata_models: %w[Event], read_action: "list_events"},
      #     "documents" => {models: %w[Document]}
      #   }
      attr_reader :areas

      # @param areas [Hash{String, Symbol=>Hash}]
      # @raise [ArgumentError] for a rule key other than models, metadata_models and read_action
      def areas=(areas)
        @areas = areas.to_h do |area, rule|
          rule = rule.to_h.symbolize_keys
          unknown = rule.keys - %i[models metadata_models read_action]
          raise ArgumentError, "config.areas[#{area.to_s.inspect}] takes models, metadata_models and read_action, not #{unknown.join(", ")}" if unknown.any?
          [area.to_s, {models: Array(rule[:models]).map(&:to_s).freeze, metadata_models: Array(rule[:metadata_models]).map(&:to_s).freeze,
                       read_action: rule[:read_action]&.to_s}.freeze]
        end.freeze
      end

      # @param names [Array<String, Class>] the lookup list models, by name
      def lookup_lists=(names)
        @lookup_lists = Array(names).map(&:to_s).freeze
      end

      # What lists page with, and what a `table` action's search, sort and
      # filters come from: the app's own paging and table libraries. Under
      # the :pagy adapter it is Adapters::Lists::Pagy unless the app names
      # its own, which may extend that module for its paging. An object (or
      # its class name) that answers:
      # - paginate(collection, page:, page_size:): the page's records and
      #   the pagination the view renders;
      # - filters(table): each filter's input name and JSON schema, as a Hash;
      # - search?(table): whether the table takes a search;
      # - query(table, user:, params:): the person's records, searched, sorted and filtered;
      # - metadata(table, user:, params:): what the view sends about the table;
      # - list_meta(pagination, metadata): what a list sends agents beside its
      #   summaries; metadata is nil for a list with no table, or an agent
      #   that did not ask for it.
      #
      # @param adapter [Object, String]
      attr_writer :list_adapter

      # @return [Object] the list adapter
      # @raise [ArgumentError] when the app has none
      # @api private
      def list_adapter!
        adapter = @list_adapter || (Adapters::Lists::Pagy if Adapters.declared?(:pagy))
        raise ArgumentError, "Paging a list needs the :pagy adapter, or config.list_adapter: what the app pages and queries tables with" unless adapter
        adapter.is_a?(String) ? adapter.constantize : adapter
      end

      # @return [String] the scope an action of this kind needs
      def scope_for(kind) = (kind == :read) ? scopes.fetch(:read) : scopes.fetch(:write)
    end
  end
end
