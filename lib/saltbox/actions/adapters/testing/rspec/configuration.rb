require "saltbox/actions/adapters/testing/configuration"

module Saltbox
  module Actions
    module Adapters
      module Testing
        module RSpec
          class Configuration < Testing::Configuration
            # @api private
            AGENT = "RSpec agent".freeze

            attr_writer :spec_root

            def spec_root = Pathname(@spec_root || Rails.root.join("spec/actions"))
          end
        end
      end
    end
  end
end
