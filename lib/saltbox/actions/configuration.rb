module Saltbox
  module Actions
    # What the app decides, set once in config/initializers/saltbox_actions.rb. Every
    # setting has a default that works for a plain Rails app, so an app sets
    # only what differs.
    #
    # Hooks that wrap work take the work as a callable: call it, inside
    # whatever the app sets up, and return its value.
    #
    # @example
    #   Saltbox::Actions.configure do |config|
    #     config.app_name = "Acme"
    #     config.adapters = [:pundit, :controller, :mcp, :paper_trail]
    #     config.refresh_caller { |caller| caller.with(user: User.active.find(caller.user.id)) }
    #     config.around_invocation { |caller, run| caller.user.org.with_tenant { run.(caller) } }
    #     config.around_perform { |invocation, run| ::PaperTrail.request(whodunnit: invocation.caller.user.id) { run.() } }
    #     config.on_changes { |changes, invocation| publish(changes, invocation) }
    #     config.map_error(MyApp::DomainError) { |error| Saltbox::Actions::Error::ValidationFailed.new(error.message) }
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
      # @return [Boolean] whether every action's model must belong to an area (see #area_for)
      attr_accessor :require_area
      # @return [Array<String>] the areas find_action lists first, in this order;
      #   the rest follow alphabetically, then actions with no area
      attr_accessor :area_order
      # @return [Array<String>] the models that are lookup lists: short lists
      #   anyone who can pick from them may name by id or by name, such as
      #   event types; a reference to one skips the policy scope (see Base#resolve_reference)
      attr_reader :lookup_lists
      # @return [Integer] page_size when a paginated list's caller leaves it out
      attr_accessor :page_size
      # @return [Integer] the largest page_size a paginated list's caller may ask for
      attr_accessor :max_page_size
      # @return [Object, nil] what lists page and tables query with (see #list_adapter=)
      attr_reader :list_adapter
      # @return [Integer, #call] the most items an array attribute takes
      attr_writer :max_array_items
      # @return [Boolean] whether Invocation refuses a person who lacks an action's
      #   declared permissions; when false they only decide the actions list
      attr_accessor :enforce_permissions
      # @return [Boolean] whether Invocation refuses an agent a :confirm action
      #   unless the #confirm hook approves it (true by default; with no hook,
      #   every such call is refused); set false on purpose to let agents on
      #   the API, MCP and a browser page run :confirm actions with nothing checked
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
        @permissions_held = ->(_caller) { [] }
        @around_invocation = ->(caller, run) { run.call(caller) }
        @around_perform = ->(_invocation, run) { run.call }
        @on_changes = ->(_changes, _invocation) {}
        @after_change_commit = ->(_invocation, _result) {}
        @confirm = nil
        @approvals = {user: "User"}
        @on_access_refused = ->(_caller, _action) { Error::InsufficientScope.new }
        @on_forbidden_fields = ->(_caller, _action, fields) { Error::Forbidden.for_fields(fields) }
        @feature_enabled = ->(_key, _caller) { true }
        @validate_feature = ->(_key) {}
        @area_for = nil
        @areas = {}.freeze
        @lookup_lists = [].freeze
        @page_size = 25
        @max_page_size = 100
        @list_adapter = nil
        @refresh_caller = ->(caller) { caller }
        @check_caller = ->(_caller) {}
        @schema_user = nil
        @error_mappings = []
        @action_checks = []
        @registry_checks = []
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

      # @return [Integer]
      def max_array_items = @max_array_items.respond_to?(:call) ? @max_array_items.call : @max_array_items

      # The set-up each invocation, catalog listing and search runs inside:
      # the tenant, time zone and Current of the caller, once #refresh_caller
      # has refreshed it. The block calls run with the caller.
      #
      # @yieldparam caller [Caller] the refreshed caller
      # @yieldparam run [Proc] takes the caller
      def around_invocation(&block) = block ? @around_invocation = block : @around_invocation

      # Wraps each action's work, inside the invocation's set-up and outside
      # its transaction: the place for an audit trail's request info.
      #
      # @yieldparam invocation [Invocation]
      # @yieldparam run [Proc]
      def around_perform(&block) = block ? @around_perform = block : @around_perform

      # Receives every record a change changed, inside the change's
      # transaction, so an event stored in the same database commits with it.
      #
      # @yieldparam changes [Array<Array(String, String, String)>] each record's type, id and event
      # @yieldparam invocation [Invocation]
      def on_changes(&block) = block ? @on_changes = block : @on_changes

      # Runs after a change commits, with its result: once every enclosing
      # transaction has committed, and never when one rolls back. It may run
      # after the invocation and the caller's own request context have
      # ended (Current, around_invocation's and around_perform's set-up), so it
      # sets up any context it needs itself; invocation.invocation_id and
      # invocation.caller stay readable.
      #
      # @yieldparam invocation [Invocation]
      # @yieldparam result [Result]
      def after_change_commit(&block) = block ? @after_change_commit = block : @after_change_commit

      # Called when a caller's access (Caller#access) does not reach the
      # action. Returns the Error to raise; the place to note the refusal
      # or ask the person.
      #
      # @yieldparam caller [Caller]
      # @yieldparam action [Class]
      # @yieldreturn [Error]
      def on_access_refused(&block) = block ? @on_access_refused = block : @on_access_refused

      # Called when a caller sends a field of the action's model they may not
      # set, whether their input schema leaves it out or the policy refuses
      # it for the record. Returns the Error to raise, a Forbidden, so the
      # refusal can say why in your words. The default names each field:
      # "You can't change notes."
      #
      # @yieldparam caller [Caller]
      # @yieldparam action [Class]
      # @yieldparam fields [Array<String>] each field sent that the caller may not set
      # @yieldreturn [Error::Forbidden]
      def on_forbidden_fields(&block) = block ? @on_forbidden_fields = block : @on_forbidden_fields

      # Approves a :confirm action for an agent, while #enforce_confirm is on (the default):
      # the place to ask the person through the app's own channel. Return
      # true to run it; anything else refuses with confirmation_required.
      # Raise an Error to refuse in your own words. Called after every other
      # check and the input's, outside the change's transaction; called from
      # Caller#confirm! inside it.
      #
      # @yieldparam invocation [Invocation] the call: its action, caller and arguments;
      #   from Caller#confirm!, the outer action's arguments
      # @yieldparam action [Class] the :confirm action to approve; the
      #   invocation's own, or the one Caller#confirm! names
      # @yieldreturn [Boolean]
      #
      # With :approvals declared and no hook set, it is Approval.redeem!.
      def confirm(&block)
        return @confirm = block if block
        @confirm || (Adapters.declared?(:approvals) ? Adapters::Confirmation::Approvals.confirm : ->(_invocation, _action) { false })
      end

      # The app's classes the :approvals adapter's Approval belongs to, by
      # name: the person (user, the caller's user), and optionally the tenant
      # each approval is kept in and the connection the caller came through.
      # With a tenant, the current one is current_tenant's, or acts_as_tenant's.
      # message, given the request, is what the agent is told until the
      # person approves.
      #
      # @return [Hash{Symbol=>String, Proc}]
      #
      # @example
      #   config.approvals = {user: "Account", tenant: "Org", connection: "Oauth::Connection",
      #     message: ->(approval) { "Approve it under Settings, Connections, then call it again." }}
      attr_reader :approvals

      # @param settings [Hash]
      # @raise [ArgumentError] for an unknown key, or no user
      def approvals=(settings)
        settings = settings.to_h.symbolize_keys
        unknown = settings.keys - %i[user tenant connection current_tenant message]
        raise ArgumentError, "config.approvals takes user, tenant, connection, current_tenant and message, not #{unknown.join(", ")}" if unknown.any?
        raise ArgumentError, "config.approvals names the person's class as user:" unless settings[:user]
        @approvals = settings.freeze
      end

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

      # The area an action's model belongs to, such as "events". With #areas
      # given, the area whose models name it (Areas.area_for).
      #
      # @yieldparam model [Class]
      # @yieldreturn [String, nil]
      def area_for(&block)
        return @area_for = block if block
        @area_for || ->(model) { Areas.area_for(model.name) }
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
      # filters come from: the app's own paging and table libraries. An
      # object (or its class name) that answers:
      # - paginate(collection, page:, page_size:): the page's records and
      #   the pagination the view renders;
      # - filters(table): each filter's input name and JSON schema, as a Hash;
      # - search?(table): whether the table takes a search;
      # - query(table, user:, params:): the person's records, searched, sorted and filtered;
      # - metadata(table, user:, params:): what the view sends about the table.
      #
      # @param adapter [Object, String]
      attr_writer :list_adapter

      # @return [Object] the list adapter
      # @raise [ArgumentError] when the app has none
      # @api private
      def list_adapter!
        adapter = @list_adapter or raise ArgumentError, "Paging a list needs config.list_adapter: what the app pages and queries tables with"
        adapter.is_a?(String) ? adapter.constantize : adapter
      end

      # The caller as it stands now, before each invocation, catalog listing
      # and find_action search: a revoked token or ended access stops the
      # next call. Return a new caller; a caller cannot change.
      #
      # @yieldparam caller [Caller]
      # @yieldreturn [Caller]
      def refresh_caller(&block) = block ? @refresh_caller = block : @refresh_caller

      # Refuses a caller inside the app's set-up (#around_invocation), once
      # its tenant is set: the place for a rule on a whole surface, such as
      # a permission the in-app chat needs. Raise an Error to refuse.
      #
      # @yieldparam caller [Caller] the refreshed caller
      def check_caller(&block) = block ? @check_caller = block : @check_caller

      # Who a create or update's input schema is built for where there is
      # no caller: the committed catalog (config/actions.json),
      # `rails actions:check` and the registry spec or test, the generator's
      # field list, and the schema matchers without `as:`. A user
      # holding every permission, so the catalog lists every field.
      # Callers never see it: each gets the fields their policy permits them. Without it the policy is asked
      # with no person (nil). The block calls run with the user, inside
      # whatever the policy needs, such as a tenant.
      #
      # @example A policy that needs a person, in a multi-tenant app
      #   config.schema_user { |run| ActsAsTenant.without_tenant { run.call(User.new(admin: true)) } }
      #
      # @yieldparam run [Proc] takes the user
      def schema_user(&block) = block ? @schema_user = block : @schema_user

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
      # @api private
      attr_reader :error_mappings

      # Adds a check for each action, beside the gem's own, run by
      # `rails actions:check` (Registry.check!), never at boot, so it may read
      # the database.
      #
      # @yieldparam action [Class]
      # @yieldreturn [Array<String>] each problem and its fix
      # @return [void]
      def check_action(&block) = @action_checks << block

      # @return [Array<Proc>]
      # @api private
      attr_reader :action_checks

      # Adds a check over every action at once, run by `rails actions:check`
      # once each action's checks pass.
      #
      # @yieldparam actions [Array<Class>]
      # @return [void]
      def check_registry(&block) = @registry_checks << block

      # @return [Array<Proc>] the app's checks, and Areas.validate! when #areas are given
      # @api private
      def registry_checks = areas.any? ? [->(_actions) { Areas.validate! }, *@registry_checks] : @registry_checks

      # @return [String] the scope an action of this kind needs
      def scope_for(kind) = (kind == :read) ? scopes.fetch(:read) : scopes.fetch(:write)
    end
  end
end
