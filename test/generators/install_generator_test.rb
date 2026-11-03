require "test_helper"
require "generators/actions/install/install_generator"
require "tmpdir"

class InstallGeneratorTest < ActiveSupport::TestCase
  test "rails g actions:install writes the initializer with every adapter commented out" do
    assert_equal Saltbox::Actions::Generators::InstallGenerator, Rails::Generators.find_by_namespace("actions:install")
    Dir.mktmpdir("install-generator") do |destination|
      capture_io { Saltbox::Actions::Generators::InstallGenerator.start([], destination_root: destination) }
      source = File.read(File.join(destination, "config/initializers/saltbox_actions.rb"))
      Saltbox::Actions::Adapters::LIST.each_key { assert_includes source, "# #{it.inspect}," }
    end
  end
end
