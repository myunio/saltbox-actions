module Saltbox
  module Actions
    # Reads an action's settings from its class name, so each action declares
    # only what the name cannot give. For Event::Type::CreateAction:
    # - the model is the namespace, Event::Type;
    # - the action words are the words before "Action": ["create"];
    # - the verb is the first action word: "create".
    #
    # VERBS lists the common verbs, each with its kind (read, change or
    # destructive) and whether it works on one record named by an id. The
    # same verb does the same job everywhere, because the words are public:
    # the action name is the tool name agents call over MCP
    # (create_event_type), and the CLI command is built from the same words.
    module Naming
      extend ActiveSupport::Concern

      # Each verb's kind, and whether it works on one record named by an id.
      # A verb outside this table must declare its kind. A token with only
      # the read scope may run every read, so a verb's kind decides what that
      # token can do.
      VERBS = {
        "list" => {kind: :read, id: false},
        "show" => {kind: :read, id: true},
        "export" => {kind: :read, id: false},
        "create" => {kind: :change, id: false},
        "update" => {kind: :change, id: true},
        "cancel" => {kind: :change, id: true},
        "reinstate" => {kind: :change, id: true},
        "publish" => {kind: :change, id: true},
        "delete" => {kind: :destructive, id: true}
      }.freeze
      # Rails verbs, and the verb actions use instead. An action named with the
      # Rails verb stops the boot: Event::DestroyAction must be Event::DeleteAction.
      RAILS_SPELLINGS = {"destroy" => "delete", "index" => "list", "edit" => "update", "new" => "create", "get" => "show"}.freeze
      # Verbs whose tool name uses the model's plural: list_events, not list_event.
      PLURAL_VERBS = %w[list export].freeze
      # The policy query each verb asks. A verb not listed asks the query of
      # its own name: cancel asks cancel?.
      VERB_QUERIES = {"list" => :index?, "show" => :show?, "create" => :create?, "update" => :update?, "delete" => :destroy?}.freeze
      KINDS = %i[read change destructive].freeze

      class_methods do
        # @return [Array<String>] the words before Action: ["show", "history"] for Event::ShowHistoryAction
        def action_words = name.demodulize.delete_suffix("Action").underscore.split("_")

        # @return [String] the first action word
        def verb = action_words.first

        # @return [Boolean] whether the verb is in VERBS
        def table_verb? = VERBS.key?(verb)

        # @return [Boolean] whether the class name has words after the verb, as ShowHistoryAction does
        def more_than_verb? = action_words.size > 1

        # The model the action works on: the class's namespace, unless declared.
        # A top-level action, such as WhoamiAction, has none, and neither has
        # an action with a declared name unless it declares one.
        #
        # @param value [Class<ActiveRecord::Base>, nil] declares the model
        # @return [Class<ActiveRecord::Base>, nil]
        def model(value = nil)
          return @model = value if value
          return @model if declared_name
          @model || name.deconstantize.presence&.safe_constantize
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
          noun = model && (PLURAL_VERBS.include?(verb) ? model.model_name.plural : model.model_name.singular)
          [verb, noun, *action_words.drop(1)].compact.join("_")
        end

        # @return [Array<String>] the CLI command's words: the declared ones (see Declarations#cli),
        #   otherwise ["events", "update"], ["event-types", "create"]
        def cli_command
          return declared_cli[:command] if declared_cli
          [model&.model_name&.route_key&.dasherize, action_words.join("-")].compact
        end

        # @return [String, nil] the name declared with action_name
        def declared_name = @declared_name

        # @return [Symbol, nil] :read, :change or :destructive, from VERBS or from the class's `kind`
        #   declaration; an action with a declared name always declares it
        def kind = declared_name ? declared_kind : (VERBS.dig(verb, :kind) || declared_kind)

        # @return [Boolean] whether the action works on one record named by an id
        def takes_id? = (!declared_name && VERBS.dig(verb, :id) == true) || arguments.key?("id")

        # @return [Symbol] the policy rule the action checks: the one declared with the class-level
        #   `authorize`, otherwise the verb's from VERB_QUERIES (destroy? for delete), otherwise "<verb>?"
        #   (an action with a declared name has only the declared one)
        def policy_query = declared_query || (declared_name ? nil : VERB_QUERIES.fetch(verb) { :"#{verb}?" })

        # @return [String, nil] the area its model belongs to, from Configuration#area_for
        def area = model && Actions.config.area_for.call(model)

        # @return [String] the action's key in config/locales/actions.en.yml: event/update for Event::UpdateAction
        def locale_key = name.underscore.delete_suffix("_action")

        # @return [String] the declared title (see Declarations#title), the locale file's,
        #   or one built from the class name: "Update event", "List events"
        def title(value = nil)
          return @declared_title = value if value
          return @declared_title if @declared_title
          noun = model&.model_name&.human&.downcase
          noun = noun&.pluralize if PLURAL_VERBS.include?(verb)
          default = [verb.humanize, noun, *action_words.drop(1)].compact.join(" ")
          I18n.t("actions.#{locale_key}.title", default:)
        end

        # Tells an agent when to use the action. Declared in the class, or read
        # from the locale file.
        #
        # @param value [String, nil] declares it
        # @return [String, nil]
        def description(value = nil)
          return @declared_description = value.squish if value
          @declared_description || I18n.t("actions.#{locale_key}.description", default: nil)&.squish
        end

        # @param field [String]
        # @return [String, nil] the locale file's description of one input: the action's own, or the shared one
        def field_description(field)
          I18n.t("actions.#{locale_key}.fields.#{field}", default: I18n.t("actions.shared.fields.#{field}", default: nil))&.squish
        end
      end
    end
  end
end
