require "paper_trail"

module Saltbox
  module Actions
    module Adapters
      module Audit
        # Uses PaperTrail as a source for the change collection: every version
        # a change writes is noted, so Configuration#on_changes hears of each
        # versioned record, dependents included. ChangeTracking does the same
        # without PaperTrail; with both, each record is noted once. Wrap each run
        # in a PaperTrail request so each version names the person and the agent.
        # Declaring :paper_trail runs install! once the app has loaded; the
        # request stays the app's, since what each version records depends on
        # its versions table.
        #
        # @example config/initializers/saltbox_actions.rb
        #   Saltbox::Actions.configure do |config|
        #     config.adapters = [:pundit, :paper_trail]
        #     config.around_perform do |invocation, run|
        #       Saltbox::Actions::Adapters::Audit::PaperTrail.request(invocation, agent: invocation.caller.agent_name) { run.() }
        #     end
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

          # @param invocation [Invocation]
          # @param controller_info [Hash] extra columns for each version, such as agent and surface
          # @yield the action's run
          # @return [Object] the block's value
          def self.request(invocation, **controller_info, &)
            ::PaperTrail.request(whodunnit: invocation.caller.user.id, controller_info:, &)
          end
        end
      end
    end
  end
end
