require "saltbox/actions/testing/configuration"

module Saltbox
  module Actions
    module RSpec
      class Configuration < Testing::Configuration
        AGENT = "RSpec agent".freeze

        attr_writer :spec_root

        def spec_root = Pathname(@spec_root || Rails.root.join("spec/actions"))
      end
    end
  end
end
