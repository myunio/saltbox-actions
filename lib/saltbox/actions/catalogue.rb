module Saltbox
  module Actions
    # Decides which actions a caller sees in the actions list, and what each
    # entry says. An action is listed only when all four hold:
    # - the action's feature is on for the caller;
    # - the connection's access reaches it (Caller#access);
    # - the token has the scope the action needs;
    # - the person holds the permissions it declares, or, declaring none, the policy allows their role.
    # Permission on the specific record is checked again when the action runs.
    module Catalogue
      extend ActiveSupport::Concern

      class_methods do
        # @param caller [Caller]
        # @return [Boolean] whether the action's feature is on for the caller, or the action needs none
        def enabled_for?(caller) = feature.nil? || Actions.config.feature_enabled.call(feature, caller)

        # @param caller [Caller]
        # @return [Boolean] whether the actions list shows it to this caller: all four checks above
        def available_to?(caller)
          enabled_for?(caller) && caller.reaches?(self) && caller.allows?(scope) && permitted_for?(caller)
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
        # closed to an agent by its `connections` declaration (see
        # Caller#agent_allowed?).
        #
        # @param caller [Caller]
        # @return [Boolean]
        def runnable_for?(caller) = available_to?(caller) && caller.agent_allowed?(self)

        # @return [String] the token scope it needs: the read scope for a read, the write scope for anything else
        def scope = Actions.config.scope_for(kind)

        # @return [Hash] the action's entry in the actions list and in config/actions.json
        def definition
          {"name" => action_name, "title" => title, "description" => description, "area" => area,
           "kind" => kind.to_s, "idempotent" => idempotent?, "scope" => scope, "connections" => connections.to_s,
           "permissions" => permissions&.grep(String), "permissions_any_of" => permissions&.grep(Array)&.presence,
           "mcp_core" => mcp_core?, "cli" => {"command" => cli_command, "aliases" => declared_cli&.fetch(:aliases)&.presence,
                                              "args" => cli_args, "columns" => cli_columns}.compact,
           "input_schema" => input_schema, "output_schema" => output_schema}.compact
        end

        # @return [Array<String>] the CLI command's positional arguments: the declared ones,
        #   otherwise id when the action works on one record
        def cli_args = declared_cli&.fetch(:args) || (takes_id? ? ["id"] : [])
      end
    end
  end
end
