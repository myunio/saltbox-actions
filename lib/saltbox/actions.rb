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
require "saltbox/actions/callbacks"
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
  # authorization library, the JSON API, MCP, a tenant, feature flags, an
  # audit trail, paging) are adapters, each switched on by name in the one
  # configure block, which holds settings only:
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
  # What the app adds to every call (who the caller is now, its time zone,
  # how an error reaches the caller) goes in its ApplicationAction, as
  # callbacks, rescue_from and the methods the gem calls; see Callbacks.
  module Actions
    class << self
      # @return [Configuration]
      def config = @config ||= Configuration.new

      # @yieldparam config [Configuration]
      # @return [void]
      def configure = yield(config)

      # Runs the block as the caller, inside the base class's invocation
      # callbacks (Callbacks), on an instance of the base class
      # (Configuration#base_class) built with the caller and no input: the
      # caller is refreshed (Base#refresh_caller), each declared adapter
      # sets up, then the app's callbacks run. Every actions list,
      # find_action search and schema check for a caller runs inside it, as
      # every invocation runs inside its own action's.
      #
      # @param caller [Caller]
      # @yieldparam fresh [Caller] the caller as the app refreshed it
      # @return [Object] the block's value
      # @raise [Error] when the refresh or a callback refuses the caller
      def within(caller)
        setup = config.base.new(current_caller: caller)
        setup.run_callbacks_around(:invocation) { yield setup.current_caller }
      end

      # @return [void] forgets the configuration; for the gem's own specs
      # @api private
      def reset_config! = @config = nil
    end
  end
end
