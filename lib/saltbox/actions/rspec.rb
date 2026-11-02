require "saltbox/actions"
require "saltbox/actions/rspec/configuration"
require "saltbox/actions/rspec/helpers"
require "saltbox/actions/rspec/matchers"
require "saltbox/actions/rspec/shared_examples"

module Saltbox
  module Actions
    # The RSpec layer, loaded the way pundit/rspec is:
    #
    #   # spec/rails_helper.rb
    #   require "saltbox/actions/rspec"
    #
    # Specs under spec/actions/ get `type: :action`, which includes the
    # helpers (callers for each surface and #run) and the matchers.
    # described_class is the action. The app says how to build a caller for
    # a person on each surface, since people and tokens are its own models:
    #
    #   Saltbox::Actions::RSpec.configure do |config|
    #     config.caller_for(:mcp) { |account, scopes:| ApplicationAction::Caller.connection(create(:token, account:, scopes:), surface: "mcp") }
    #   end
    module RSpec
      class << self
        # @return [Configuration]
        def config = @config ||= Configuration.new

        # @yieldparam config [Configuration]
        def configure = yield(config)
      end
    end
  end
end

::RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/actions/}) { |metadata| metadata[:type] ||= :action }
  config.include Saltbox::Actions::RSpec::Helpers, type: :action
  config.include Saltbox::Actions::RSpec::Matchers, type: :action
end
