require "active_support"
require "active_support/core_ext"
require "active_record"
require "json"
require "digest"

require "saltbox/actions/version"
require "saltbox/actions/action_paths"
require "saltbox/actions/adapters"
require "saltbox/actions/configuration"
require "saltbox/actions/current"
require "saltbox/actions/error"
require "saltbox/actions/result"
require "saltbox/actions/caller"
require "saltbox/actions/params"
require "saltbox/actions/naming"
require "saltbox/actions/summary"
require "saltbox/actions/declarations"
require "saltbox/actions/inputs"
require "saltbox/actions/casting"
require "saltbox/actions/schema"
require "saltbox/actions/arguments"
require "saltbox/actions/catalog"
require "saltbox/actions/rendering"
require "saltbox/actions/permitting"
require "saltbox/actions/lists"
require "saltbox/actions/authorization"
require "saltbox/actions/invocation"
require "saltbox/actions/change_tracking"
require "saltbox/actions/registry"
require "saltbox/actions/areas"
require "saltbox/actions/finder"
require "saltbox/actions/record_data"
require "saltbox/actions/agent_tools"
require "saltbox/actions/base"
require "saltbox/actions/railtie" if defined?(Rails::Railtie)

module Saltbox
  # An action is one thing a person can do in an app, such as updating an
  # event. It is written once, as a class under app/actions/, and every way
  # into the app runs the same class: the screens, a JSON API, the CLI, MCP
  # for AI agents, and an in-app assistant.
  #
  # The app's base class inherits from Base. The optional parts (an
  # authorization library, the JSON API, MCP, an audit trail) are adapters,
  # each switched on by name in the one configure block; the base class then
  # includes the declared authorization adapter itself:
  #
  # @example config/initializers/saltbox_actions.rb
  #   Saltbox::Actions.configure do |config|
  #     config.adapters = [:pundit, :controller, :mcp]
  #   end
  #
  # @example
  #   class ApplicationAction < Saltbox::Actions::Base
  #   end
  #
  #   class Events::UpdateAction < ApplicationAction
  #     def perform
  #       event.update!(permitted_attributes(event))
  #       render :show
  #     end
  #   end
  #
  # What the app decides (its name, its tenancy, its audit trail, how a
  # change is announced) goes in the same configure block; see Configuration
  # and Adapters.
  module Actions
    class << self
      # @return [Configuration]
      def config = @config ||= Configuration.new

      # @yieldparam config [Configuration]
      # @return [void]
      def configure = yield(config)

      # Runs the block as the caller: refreshed (Configuration#refresh_caller),
      # inside the app's set-up for an invocation
      # (Configuration#around_invocation: its tenant, time zone, Current),
      # then checked (Configuration#check_caller). Every invocation, catalog
      # listing and find_action search runs inside it.
      #
      # @param caller [Caller]
      # @yieldparam fresh [Caller] the caller as the app refreshed it
      # @return [Object] the block's value
      # @raise [Error] when the refresh or the check refuses the caller
      def within(caller, &block)
        fresh = config.refresh_caller.call(caller)
        config.around_invocation.call(fresh, ->(set_up) {
          config.check_caller.call(set_up)
          block.call(set_up)
        })
      end

      # @return [void] forgets the configuration; for the gem's own specs
      # @api private
      def reset_config! = @config = nil
    end
  end
end
