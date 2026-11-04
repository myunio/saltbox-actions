require "paper_trail"

module Saltbox
  module Actions
    module Adapters
      module Audit
        # Records who made each change with PaperTrail. Every action's work
        # runs in a PaperTrail request, as a controller's does, stamped with
        # the action's user_for_paper_trail (the person's id by default, nil
        # for a system caller) and info_for_paper_trail (the versions table's
        # other columns, none by default): PaperTrail's own names for its
        # controller methods. Every version a change writes is also noted
        # into the change collection, so the changes.saltbox_actions
        # notification names each versioned record, dependents included.
        # ChangeTracking does the same without PaperTrail; with both, each
        # record is noted once.
        #
        # @example app/actions/application_action.rb
        #   class ApplicationAction < Saltbox::Actions::Base
        #     private
        #
        #     def info_for_paper_trail = {agent: current_caller.agent_name, invocation_id:}
        #   end
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
