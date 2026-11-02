module Saltbox
  module Actions
    # Reads an action's settings from its class name, so each action declares
    # only what the name cannot give. Actions are named like controllers: a
    # plural resource namespace, then the action words. For
    # Event::Types::CreateAction:
    # - the model is the namespace, singular, as wrap_parameters finds a
    #   controller's model: Event::Type;
    # - the action words are the words before "Action": ["create"];
    # - the verb is the first action word: "create".
    #
    # The verb table (#verbs) gives each verb its kind (read, change or
    # destructive), whether it works on one record named by an id (a member
    # action, as routes say `on: :member`) and whether running it again
    # changes nothing more. The same verb does the same job everywhere,
    # because the words are public: the action name is the tool name agents
    # call over MCP (create_event_type), and the CLI command is built from
    # the same words.
    module Naming
      extend ActiveSupport::Concern

      # The verbs every app starts with. An app adds its own with define_verb.
      # A token with only the read scope may run every read, so a verb's kind
      # decides what that token can do.
      VERBS = {
        "list" => {kind: :read, member: false, idempotent: true},
        "show" => {kind: :read, member: true, idempotent: true},
        "export" => {kind: :read, member: false, idempotent: false},
        "create" => {kind: :change, member: false, idempotent: false},
        "update" => {kind: :change, member: true, idempotent: true},
        "cancel" => {kind: :change, member: true, idempotent: false},
        "reinstate" => {kind: :change, member: true, idempotent: false},
        "publish" => {kind: :change, member: true, idempotent: false},
        "delete" => {kind: :destructive, member: true, idempotent: true}
      }.freeze
      # Rails verbs, and the verb actions use instead. An action named with the
      # Rails verb stops the boot: Events::DestroyAction must be Events::DeleteAction.
      RAILS_SPELLINGS = {"destroy" => "delete", "index" => "list", "edit" => "update", "new" => "create", "get" => "show"}.freeze
      # Verbs whose tool name uses the model's plural: list_events, not list_event.
      PLURAL_VERBS = %w[list export].freeze
      # The policy query each verb asks. A verb not listed asks the query of
      # its own name: cancel asks cancel?.
      VERB_QUERIES = {"list" => :index?, "show" => :show?, "create" => :create?, "update" => :update?, "delete" => :destroy?}.freeze
      KINDS = %i[read change destructive].freeze
      ON = %i[member collection].freeze

      included do
        class_attribute :verbs, instance_accessor: false, default: VERBS
      end

      class_methods do
        # Adds verbs to the table, for this class and every class below it,
        # the way an app adds inflections. Declared once in the app's base
        # class; a verb used by one action can declare its kind in that
        # action instead (Declarations#kind).
        #
        # @param names [Array<Symbol, String>]
        # @param kind [Symbol] :read, :change or :destructive
        # @param on [Symbol] :member for a verb that works on one record named by an id, or :collection
        # @param idempotent [Boolean] whether running it again with the same input changes nothing more
        # @param connections [Symbol, nil] the verb's connections rule (see Declarations#connections);
        #   left out, its kind's
        # @return [void]
        # @raise [ArgumentError] for an unknown kind, on: or connections rule, or a Rails spelling
        #
        # @example In ApplicationAction
        #   define_verb :archive, kind: :change, on: :member, idempotent: true
        #   define_verb :void, kind: :destructive, on: :member, connections: :never
        def define_verb(*names, kind:, on: :collection, idempotent: false, connections: nil)
          raise ArgumentError, "define_verb #{names.join(", ")}: kind is :read, :change or :destructive, not #{kind.inspect}" unless KINDS.include?(kind)
          raise ArgumentError, "define_verb #{names.join(", ")}: on is :member or :collection, not #{on.inspect}" unless ON.include?(on)
          if connections && !Declarations::CONNECTIONS.include?(connections)
            raise ArgumentError, "define_verb #{names.join(", ")}: connections is :allowed, :confirm or :never, not #{connections.inspect}"
          end
          names = names.map(&:to_s)
          spelled = names.select { RAILS_SPELLINGS.key?(it) }
          raise ArgumentError, "#{spelled.map { "#{it} is spelled #{RAILS_SPELLINGS[it]}" }.join(", ")} in actions" if spelled.any?
          rule = {kind:, member: on == :member, idempotent:, connections:}.compact.freeze
          self.verbs = verbs.merge(names.to_h { [it, rule] }).freeze
        end

        # @return [Array<String>] the words before Action: ["show", "history"] for Events::ShowHistoryAction
        def action_words = name.demodulize.delete_suffix("Action").underscore.split("_")

        # @return [String] the first action word
        def verb = action_words.first

        # @return [Boolean] whether the verb is in the verb table
        def table_verb? = verbs.key?(verb)

        # @return [Boolean] whether the class name has words after the verb, as ShowHistoryAction does
        def more_than_verb? = action_words.size > 1

        # The model the action works on, unless declared: its namespace,
        # singular, as wrap_parameters finds a controller's model. Events gives
        # Event; Admin::Events gives Admin::Event, or else Event. A top-level
        # action, such as WhoamiAction, has none, and neither has an action
        # with a declared name unless it declares one.
        #
        # @param value [Class<ActiveRecord::Base>, nil] declares the model
        # @return [Class<ActiveRecord::Base>, nil]
        def model(value = nil)
          return @model = value if value
          return @model if declared_name || defined?(@model)
          inferred_model
        end

        # The action's name in the API, MCP and the actions list: the verb, the
        # model (plural for list and export), then any other action words.
        # An app whose names are already public declares one instead, and
        # the naming rules no longer apply: the action declares its kind,
        # and its model if it has one.
        #
        # @param value [String, nil] declares the name
        # @return [String] such as update_event, list_event_types, show_event_history or whoami
        def action_name(value = nil)
          return @declared_name = value.to_s if value
          return declared_name if declared_name
          [verb, name_noun(plural: PLURAL_VERBS.include?(verb)), *action_words.drop(1)].compact.join("_")
        end

        # @return [Array<String>] the CLI command's words: the declared ones (see Declarations#cli),
        #   otherwise ["events", "update"], ["event-types", "create"]
        def cli_command
          return declared_cli[:command] if declared_cli
          noun = action_namespace ? name_noun(plural: true) : model&.model_name&.route_key
          [noun&.dasherize, action_words.join("-")].compact
        end

        # @return [String, nil] the namespace its action folder gives its names (see ActionPaths#add)
        def action_namespace = Actions.config.action_paths.namespace_for(self)

        # The model's part of the action's name. A namespace from the action
        # folder takes the place of an isolated engine's module: Billing::Invoice
        # is billing_invoice, or pay_invoice under the namespace "pay".
        #
        # @param plural [Boolean]
        # @return [String, nil]
        def name_noun(plural:)
          return unless model
          names = model.model_name
          return plural ? names.plural : names.singular unless (namespace = action_namespace)
          "#{namespace}_#{plural ? names.param_key.pluralize : names.param_key}"
        end

        # @return [String, nil] the name declared with action_name
        def declared_name = @declared_name

        # @return [Symbol, nil] :read, :change or :destructive, from the verb table or from the class's
        #   `kind` declaration; an action with a declared name always declares it
        def kind = declared_name ? declared_kind : (verb_rule&.fetch(:kind) || declared_kind)

        # @return [Hash, nil] the verb's row in the verb table, for an action named by its verb
        def verb_rule = (verbs[verb] unless declared_name)

        # @return [Boolean] whether the action works on one record named by an id: a member verb,
        #   or `attribute :id`
        def takes_id? = verb_rule&.fetch(:member) == true || declares_id?

        # @return [Symbol] the policy rule the action checks: the one declared with `policy_rule`,
        #   otherwise the verb's from VERB_QUERIES (destroy? for delete), otherwise "<verb>?"
        #   (an action with a declared name has only the declared one)
        def policy_query = declared_query || (declared_name ? nil : VERB_QUERIES.fetch(verb) { :"#{verb}?" })

        # @return [String, nil] the area its model belongs to, from Configuration#area_for
        def area = model && Actions.config.area_for.call(model)

        # @return [String] the action's key in config/locales/actions.en.yml: events/update for Events::UpdateAction
        def locale_key = name.underscore.delete_suffix("_action")

        # @return [String, nil] its resource's key, whose fields every action of the resource shares: events
        def resource_locale_key = locale_key.rpartition("/").first.presence

        # The action's title. The locale file's wins, as Action Mailer's
        # subject does; then the one declared in the class; then one built
        # from the class name: "Update event", "List events".
        #
        # @param value [String, nil] declares it
        # @return [String]
        def title(value = nil)
          return @declared_title = value if value
          I18n.t("actions.#{locale_key}.title", default: @declared_title || built_title)
        end

        # Tells an agent when to use the action. Written in the class, beside
        # the code it describes; a locale entry, when there is one, wins, for
        # an app that serves agents in more than one language.
        #
        # @param value [String, nil] declares it
        # @return [String, nil]
        def description(value = nil)
          return @declared_description = value.squish if value
          I18n.t("actions.#{locale_key}.description", default: @declared_description)&.squish
        end

        # One input's description, from the first that has it: the action's
        # locale entry (actions.events/update.fields.title), its resource's
        # (actions.events.fields.title), the attribute's description:, then
        # the shared one (actions.shared.fields.title).
        #
        # @param field [String]
        # @return [String, nil]
        def field_description(field)
          keys = [:"actions.#{locale_key}.fields.#{field}"]
          keys << :"actions.#{resource_locale_key}.fields.#{field}" if resource_locale_key
          declared = declared_attributes.dig(field.to_s, :description)
          defaults = declared ? [*keys.drop(1), declared] : [*keys.drop(1), :"actions.shared.fields.#{field}", ""]
          I18n.t(keys.first, default: defaults).squish.presence
        end

        private

        def built_title
          noun = model&.model_name&.human&.downcase
          noun = "#{action_namespace.humanize(capitalize: false)} #{noun}" if noun && action_namespace
          noun = noun&.pluralize if PLURAL_VERBS.include?(verb)
          [verb.humanize, noun, *action_words.drop(1)].compact.join(" ")
        end

        def inferred_model = Naming.model_for(name.deconstantize)
      end

      # The model a resource namespace names, found as wrap_parameters finds a
      # controller's: singular, walking out of the namespace, so
      # Admin::Events tries Admin::Event, then Event.
      #
      # @param namespace [String] such as "Admin::Events"
      # @return [Class, nil]
      def self.model_for(namespace)
        parts = namespace.split("::")
        until parts.empty?
          found = parts.join("::").classify.safe_constantize
          return found if found.is_a?(Class)
          break if parts.size == 1
          parts.delete_at(-2)
        end
        nil
      end
    end
  end
end
