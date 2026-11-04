require "paper_trail"

module Saltbox
  module Actions
    module Adapters
      module Audit
        # Records who made each change with PaperTrail. Every action's work
        # runs in a PaperTrail request, as a controller's does, stamped with
        # the action's user_for_paper_trail (the person's id by default, nil
        # for a system caller) and info_for_paper_trail (the agent, its stamp,
        # the surface, the connection and the call's id, in whichever of the
        # versions table's columns agent, agent_via, surface, connection_id
        # and invocation_id it has): PaperTrail's own names for its
        # controller methods. Every version a change writes is also noted
        # into the change collection, so the changes.saltbox_actions
        # notification names each versioned record, dependents included.
        # ChangeTracking does the same without PaperTrail; with both, each
        # record is noted once.
        #
        # @example db/migrate/..._add_agent_to_versions.rb
        #   add_column :versions, :agent, :string
        #   add_column :versions, :agent_via, :jsonb
        #   add_column :versions, :surface, :string
        #   add_column :versions, :invocation_id, :string
        module PaperTrail
          # Notes each version created into the running change collection.
          # Run once, after the app has loaded, by the :paper_trail declaration.
          #
          # @return [void]
          def self.install!
            return if @installed
            ::PaperTrail::Version.after_create { Invocation.note(item_type, item_id, event, transaction: self.class.current_transaction) }
            @installed = true
          end

          # @return [Array<String>] the versions table's columns
          # @api private
          def self.columns = ::PaperTrail::Version.column_names

          # @return [Boolean] whether install! has run
          def self.installed? = !!@installed

          # @param whodunnit [Object, nil]
          # @param controller_info [Hash]
          # @yield the action's work
          # @return [Object] the block's value
          # @api private
          def self.request(whodunnit:, controller_info:, &) = ::PaperTrail.request(whodunnit:, controller_info:, &)
        end
      end
    end
  end
end
