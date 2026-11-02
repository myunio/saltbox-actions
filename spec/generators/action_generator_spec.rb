require "generators/action/action_generator"
require "generators/rspec/action/action_generator"

RSpec.describe Saltbox::Actions::Generators::ActionGenerator do
  let(:destination) { Pathname(Dir.mktmpdir("action-generator")) }

  after { FileUtils.remove_entry(destination) }

  def generate(*args)
    capture = StringIO.new
    $stdout = capture
    described_class.start([*args, "--no-catalogue", "--test-framework=rspec"], destination_root: destination.to_s)
    capture.string
  ensure
    $stdout = STDOUT
  end

  it "is what `rails g action` finds" do
    expect(Rails::Generators.find_by_namespace("action")).to eq(described_class)
    expect(Rails::Generators.find_by_namespace("rspec:action")).to eq(Rspec::Generators::ActionGenerator)
  end

  it "writes an update action, its locale entry with the policy's fields, and its spec through the test framework" do
    generate("Event::Update")
    action = destination.join("app/actions/event/update_action.rb").read
    expect(action).to include("class Event::UpdateAction < ApplicationAction", "connections :allowed", "@event.update!(permitted_attributes(@event))")
    expect(destination.join("config/locales/actions.en.yml").read).to include("    event/update:\n      description:\n      fields:\n        title:\n")
    spec = destination.join("spec/actions/event/update_action_spec.rb").read
    expect(spec).to include("RSpec.describe Event::UpdateAction", %(it_behaves_like "refuses callers the action does not allow"), %(it_behaves_like "hides records the caller cannot see"))
  end

  it "declares kind, id and the policy rule for a verb outside the table, and asks before a destructive one" do
    generate("Event::Archive", "--kind", "destructive")
    action = destination.join("app/actions/event/archive_action.rb").read
    expect(action).to include("kind :destructive", "argument :id", "connections :confirm", "authorize :archive?")
  end

  it "refuses a Rails verb, an unknown verb without a kind, and a name that is not a model" do
    expect { described_class.new(["Event::Destroy"]).check_name }.to raise_error(Thor::Error, "destroy is spelled delete in actions")
    expect { described_class.new(["Event::Archive"]).check_name }.to raise_error(Thor::Error, /pass --kind/)
    expect { described_class.new(["Reports::Show"]).check_name }.to raise_error(Thor::Error, "Reports is not a model")
  end

  it "writes actions that pass the boot checks" do
    generate("Event::Archive", "--kind", "change")
    source = destination.join("app/actions/event/archive_action.rb").read
    klass = Class.new(ApplicationAction) { define_singleton_method(:name) { "Event::ArchiveAction" } }
    klass.class_eval(source.lines[1..-2].join)
    expect(Saltbox::Actions::Registry.problems(klass)).to eq(["EventPolicy#archive? is missing: add it, or authorize another query"])
  end
end
