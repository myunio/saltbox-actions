require "flipper"

module Saltbox
  module Actions
    module Adapters
      module Features
        # Checks an action's `feature` with Flipper: it is on when
        # Flipper.enabled?(key, *flipper_actors) says so. By default the one
        # actor is the current tenant when there is one, else the person
        # (Base#flipper_actors), so a percentage rollout stays per tenant.
        # While it is off the action is not found and the actions list leaves
        # it out.
        #
        # @example config/initializers/saltbox_actions.rb
        #   config.adapters = [:pundit, :flipper]
        #
        # @example Also turning a feature on per person
        #   class ApplicationAction < Saltbox::Actions::Base
        #     private
        #
        #     def flipper_actors = [current_tenant, current_user].compact
        #   end
        module Flipper
          # @param key [String]
          # @param actors [Array<Object>]
          # @return [Boolean]
          def self.enabled?(key, actors) = ::Flipper.enabled?(key, *actors)
        end
      end
    end
  end
end
