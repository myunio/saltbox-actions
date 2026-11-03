require "saltbox/actions"
require "saltbox/actions/adapters/testing/rspec/configuration"
require "saltbox/actions/adapters/testing/rspec/helpers"
require "saltbox/actions/adapters/testing/rspec/matchers"
require "saltbox/actions/adapters/testing/rspec/shared_examples"

module Saltbox
  module Actions
    module Adapters
      module Testing
        # The RSpec layer, loaded the way pundit/rspec is:
        #
        #   # spec/rails_helper.rb
        #   require "saltbox/actions/adapters/testing/rspec"
        #
        # Specs under spec/actions/ get `type: :action`, which includes the
        # helpers (callers for each surface and #run_action) and the matchers.
        # described_class is the action. The app says how to build a caller for
        # a person on each surface, since people and tokens are its own models:
        #
        #   Saltbox::Actions::Adapters::Testing::RSpec.configure do |config|
        #     config.caller_for(:mcp) { |user, scopes:| ApplicationAction::Caller.connection(create(:token, user:, scopes:), surface: "mcp") }
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
  end
end

::RSpec.configure do |config|
  config.define_derived_metadata(file_path: %r{/spec/actions/}) { |metadata| metadata[:type] ||= :action }
  config.include Saltbox::Actions::Adapters::Testing::RSpec::Helpers, type: :action
  config.include Saltbox::Actions::Adapters::Testing::RSpec::Matchers, type: :action
end
