require "active_support"
require "active_support/core_ext"
require "active_record"
require "json"
require "digest"

require "saltbox/actions/version"
require "saltbox/actions/configuration"
require "saltbox/actions/current"
require "saltbox/actions/error"
require "saltbox/actions/result"
require "saltbox/actions/caller"
require "saltbox/actions/params"
require "saltbox/actions/naming"
require "saltbox/actions/declarations"
require "saltbox/actions/casting"
require "saltbox/actions/schema"
require "saltbox/actions/arguments"
require "saltbox/actions/catalogue"
require "saltbox/actions/rendering"
require "saltbox/actions/permitting"
require "saltbox/actions/authorization"
require "saltbox/actions/invocation"
require "saltbox/actions/registry"
require "saltbox/actions/finder"
require "saltbox/actions/front_door"
require "saltbox/actions/base"
require "saltbox/actions/railtie" if defined?(Rails::Railtie)

module Saltbox
  # An action is one thing a person can do in an app, such as updating an
  # event. It is written once, as a class under app/actions/, and every way
  # into the app runs the same class: the screens, a JSON API, the CLI, MCP
  # for AI agents, and an in-app assistant.
  #
  # The app's base class inherits from Base and picks an authorization
  # adapter, the way a controller includes Pundit:
  #
  # @example
  #   class ApplicationAction < Saltbox::Actions::Base
  #     include Saltbox::Actions::Authorization::Pundit
  #   end
  #
  #   class Event::UpdateAction < ApplicationAction
  #     connections :allowed
  #     idempotent
  #
  #     def perform
  #       @event = policy_scope(Event).find(params[:id])
  #       authorize @event
  #       @event.update!(permitted_attributes(@event))
  #       render :show
  #     end
  #   end
  #
  # What the app decides (its name, its tenancy, its audit trail, how a
  # change is announced) goes in one configure block; see Configuration.
  module Actions
    # Adapters, loaded when first named, so an app needs only the gems of
    # those it uses.
    autoload :Controller, "saltbox/actions/controller"
    autoload :MCP, "saltbox/actions/mcp"
    autoload :RubyLLMTool, "saltbox/actions/ruby_llm"
    autoload :PaperTrail, "saltbox/actions/paper_trail"

    class << self
      # @return [Configuration]
      def config = @config ||= Configuration.new

      # @yieldparam config [Configuration]
      # @return [void]
      def configure = yield(config)

      # Runs the block as the caller, inside the app's set-up for an
      # invocation (Configuration#around_invocation): its tenant, time zone
      # and a fresh copy of the caller. Every invocation, catalogue listing
      # and find_action search runs inside it.
      #
      # @param caller [Caller]
      # @yieldparam fresh [Caller] the caller as the app refreshed it
      # @return [Object] the block's value
      def within(caller, &block) = config.around_invocation.call(caller, block)

      # @return [void] forgets the configuration; for the gem's own specs
      def reset_config! = @config = nil
    end
  end
end
