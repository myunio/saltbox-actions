module Saltbox
  module Actions
    # Decides which actions a caller sees in the actions list, and what each
    # entry says. An action whose policy is missing is never listed
    # (Authorization#policy_missing?). Otherwise it is listed only when all
    # four hold:
    # - the action's feature is on for the caller;
    # - the connection's access reaches it (Caller#access);
    # - the token has the scope the action needs;
    # - the person holds the permissions it declares, or, declaring none, the policy allows their role.
    # Permission on the specific record is checked again when the action runs.
    module Catalog
      extend ActiveSupport::Concern

      class_methods do
        # @param caller [Caller]
        # @return [Boolean] whether the action's feature is on for the caller, or the action needs none
        def enabled_for?(caller) = feature.nil? || Actions.config.feature_enabled.call(feature, caller)

        # @param caller [Caller]
        # @return [Boolean] whether the actions list shows it to this caller: its policy exists, and all four checks above
        def available_to?(caller)
          !policy_missing? && enabled_for?(caller) && caller.reaches?(self) && caller.allows?(scope) && permitted_for?(caller)
        end

        # Whether the person may use the action at all: they hold every
        # permission it declares, or, when it declares none, the adapter's
        # permitted? (the policy's role question) allows it.
        #
        # @param caller [Caller]
        # @return [Boolean]
        def permitted_for?(caller)
          return permitted?(caller.account) if permissions.nil?
          permissions_met?(Actions.config.permissions_held.call(caller))
        end

        # Whether this caller may also run it. A listed action can still be
        # closed to an agent by its `agents` declaration (see
        # Caller#agent_allowed?).
        #
        # @param caller [Caller]
        # @return [Boolean]
        def runnable_for?(caller) = available_to?(caller) && caller.agent_allowed?(self)

        # @return [String] the token scope it needs: the read scope for a read, the write scope for anything else
        def scope = Actions.config.scope_for(kind)

        # @param caller [Caller, nil] whose entry in the actions list; nil for config/actions.json
        # @param input [Schema::Input] the input it lists
        # @return [Hash] the action's entry in the actions list and in config/actions.json
        def definition(caller = nil, input: input(caller))
          {"name" => action_name, "title" => title, "description" => description, "area" => area,
           "kind" => kind.to_s, "idempotent" => idempotent?, "scope" => scope, "agents" => agents.to_s,
           "permissions" => permissions&.grep(String), "permissions_any_of" => permissions&.grep(Array)&.presence,
           "featured" => featured?, "cli" => {"command" => cli_command, "aliases" => declared_cli&.fetch(:aliases)&.presence, "args" => cli_args}.compact,
           "summary" => summary&.names, "input_schema" => input.schema,
           "output_schema" => summarizes_list? ? summary_output_schema : output_schema}.compact
        end

        # Tells an agent what a list action sends back, and where to find
        # the rest: "Returns each event's id and title. Call show_event with
        # its id for the rest."
        #
        # @return [String, nil] nil for an action that does not send summaries
        def summary_note
          return unless summarizes_list?
          note = "Returns each #{model.model_name.human.downcase}'s #{summary.names.to_sentence}."
          show = Registry.find("show_#{name_noun(plural: false)}")
          show ? "#{note} Call #{show.action_name} with its id for the rest." : note
        end

        # The JSON Schema of the body a list action renders for agents, in the
        # configured result format: its records' summaries, typed from the
        # model's columns, and the meta. Screens get the view, which `returns`
        # describes.
        #
        # @return [Hash, nil] nil for an action that does not send summaries
        def summary_output_schema
          return unless summarizes_list?
          item = {"type" => "object", "properties" => summary.names.to_h { [it, summary_field_schema(it)] },
                  "required" => summary.names, "additionalProperties" => false}
          records = {"type" => "object", "properties" => {model.model_name.plural => {"type" => "array", "items" => item}},
                     "required" => [model.model_name.plural]}
          return records if Actions.config.result_format == :envelope
          {"type" => "object", "properties" => {"data" => records, "meta" => {"type" => "object"}}, "required" => ["data"]}
        end

        # @return [Array<String>] the CLI command's positional arguments: the declared ones,
        #   otherwise id when the action works on one record
        def cli_args = declared_cli&.fetch(:args) || (takes_id? ? ["id"] : [])

        private

        # A column's type as its value's as_json sends it, or any plain value
        # for a method or a computed field. A decimal is sent as text, which
        # keeps every digit, and a time column as a full timestamp.
        def summary_field_schema(name)
          column = model.columns_hash[name] unless summary.fields[name]
          return Summary::PLAIN_SCHEMA unless column
          type = model.type_for_attribute(name).type
          schema = if model.defined_enums.key?(name) || type == :time
            {"type" => "string"}
          elsif type == :decimal
            {"type" => %w[number string]}
          else
            Schema::COLUMN_TYPES.fetch(type) { return Summary::PLAIN_SCHEMA }
          end
          column.null ? Schema.nullable(schema) : schema
        end
      end
    end
  end
end
