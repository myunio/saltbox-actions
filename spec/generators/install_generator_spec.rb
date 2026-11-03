require "generators/actions/install/install_generator"

RSpec.describe Saltbox::Actions::Generators::InstallGenerator do
  let(:destination) { Pathname(Dir.mktmpdir("install-generator")) }
  let(:initializer) { destination.join("config/initializers/saltbox_actions.rb") }

  after { FileUtils.remove_entry(destination) }

  def generate
    $stdout = StringIO.new
    described_class.start([], destination_root: destination.to_s)
  ensure
    $stdout = STDOUT
  end

  it "is what `rails g actions:install` finds" do
    expect(Rails::Generators.find_by_namespace("actions:install")).to eq(described_class)
  end

  it "lists every adapter, commented out, with what it does and the gem it needs" do
    generate
    source = initializer.read
    Saltbox::Actions::Adapters::LIST.each_value do |adapter|
      line = source.lines.find { it.include?("# #{adapter.name.inspect},") }
      expect(line).to include(adapter.summary)
      expect(line).to include(adapter.gem ? %(gem "#{adapter.gem}") : "no gem")
    end
  end

  it "writes a configure block that declares what is uncommented" do
    generate
    original = Saltbox::Actions.config
    Saltbox::Actions.reset_config!
    load initializer.to_s
    expect(Saltbox::Actions.config.adapters).to eq([])

    initializer.write(initializer.read.sub("# :mcp,", ":mcp,"))
    Saltbox::Actions.reset_config!
    load initializer.to_s
    expect(Saltbox::Actions.config.adapters).to eq([:mcp])
  ensure
    Saltbox::Actions.instance_variable_set(:@config, original)
  end
end
