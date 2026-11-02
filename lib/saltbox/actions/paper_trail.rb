require "paper_trail"

module Saltbox
  module Actions
    # Uses PaperTrail as a source for the change collection: every version
    # a change writes is noted, so Configuration#on_changes hears of each
    # versioned record, dependents included. ChangeTracking does the same
    # without PaperTrail; with both, each record is noted once. Wrap each run
    # in a PaperTrail request so each version names the person and the agent.
    #
    # @example config/initializers/actions.rb
    #   Saltbox::Actions::PaperTrail.install!
    #   Saltbox::Actions.configure do |config|
    #     config.around_run do |invocation, run|
    #       Saltbox::Actions::PaperTrail.request(invocation, agent: invocation.caller.agent) { run.() }
    #     end
    #   end
    module PaperTrail
      # Notes each version created into the running change collection.
      # Call once, after the app has loaded.
      #
      # @return [void]
      def self.install!
        return if @installed
        ::PaperTrail::Version.after_create { Invocation.note(item_type, item_id, event, transaction: self.class.current_transaction) }
        @installed = true
      end

      # @param invocation [Invocation]
      # @param controller_info [Hash] extra columns for each version, such as agent and surface
      # @yield the action's run
      # @return [Object] the block's value
      def self.request(invocation, **controller_info, &)
        ::PaperTrail.request(whodunnit: invocation.caller.account.id, controller_info:, &)
      end
    end
  end
end
