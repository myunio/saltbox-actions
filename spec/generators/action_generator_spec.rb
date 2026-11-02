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

  def generate_failing(*args)
    out = StringIO.new
    err = StringIO.new
    $stdout = out
    $stderr = err
    expect { described_class.start([*args, "--no-catalogue", "--test-framework=rspec"], destination_root: destination.to_s) }
      .to raise_error(SystemExit) { expect(it.status).to eq(1) }
    out.string + err.string
  ensure
    $stdout = STDOUT
    $stderr = STDERR
  end

  # EventPolicy with an archive? rule, which the dummy app's lacks.
  def with_archive_rule
    stub_const("EventPolicy", Class.new(EventPolicy) { def archive? = create? })
  end

  it "writes an update action asking before agents change, its locale entry with the policy's fields, and its spec" do
    generate("Event::Update")
    action = destination.join("app/actions/event/update_action.rb").read
    expect(action).to include("class Event::UpdateAction < ApplicationAction", "connections :confirm", "@event.update!(permitted_attributes(@event))")
    expect(destination.join("config/locales/actions.en.yml").read).to include("    event/update:\n      description:\n      fields:\n        title:\n")
    spec = destination.join("spec/actions/event/update_action_spec.rb").read
    expect(spec).to include("RSpec.describe Event::UpdateAction", "let(:arguments) { {id: event.id} }",
      %(it_behaves_like "refuses callers the action does not allow"), %(it_behaves_like "hides records the caller cannot see"))
    expect(spec).not_to include("unpermitted_account) {", "create(")
  end

  it "lets agents run a read, and leaves connections to the app's default_connections when it sets one" do
    expect(generate("Event::Show").then { destination.join("app/actions/event/show_action.rb").read }).to include("connections :allowed")
    with_settings(default_connections: :allowed) do
      generate("Event::Update", "--force")
      expect(destination.join("app/actions/event/update_action.rb").read).not_to include("connections")
      generate("Event::Delete", "--force")
      expect(destination.join("app/actions/event/delete_action.rb").read).to include("connections :confirm")
    end
  end

  it "lists through the policy scope alone" do
    generate("Event::List")
    action = destination.join("app/actions/event/list_action.rb").read
    expect(action).to include("@events = policy_scope(Event)")
    expect(action).not_to include("authorize")
  end

  it "declares kind, id and the policy rule for a verb outside the table, and gives its spec the id" do
    with_archive_rule
    generate("Event::Archive", "--kind", "destructive")
    action = destination.join("app/actions/event/archive_action.rb").read
    expect(action).to include("kind :destructive", "argument :id", "connections :confirm", "authorize :archive?")
    expect(destination.join("spec/actions/event/archive_action_spec.rb").read).to include("let(:arguments) { {id: event.id} }")
  end

  it "points a list action at its model's summary only when the model has none" do
    expect(generate("Event::List")).not_to include("summary Event")
    allow(ApplicationAction).to receive(:model_summaries).and_return({})
    expect(generate("Event::List", "--force")).to include("Agents get each event's full view", "`summary Event, :id, ...` in ApplicationAction")
  end

  it "refuses a Rails verb, an unknown verb without a kind, and a name that is not a model" do
    expect { described_class.new(["Event::Destroy"]).check }.to raise_error(Thor::Error, "destroy is spelled delete in actions: bin/rails g action Event::Delete")
    expect { described_class.new(["Event::Archive"]).check }.to raise_error(Thor::Error, /pass --kind/)
    expect { described_class.new(["Reports::Show"]).check }.to raise_error(Thor::Error, /Reports is not a model/)
  end

  it "writes nothing when the action would fail the boot check, and prints the fix, not the next steps" do
    output = generate_failing("Event::Archive", "--kind", "change")
    expect(output).to include("Event::ArchiveAction would not pass the boot check, so nothing was written",
      "EventPolicy#archive? is missing: add it, or authorize another query")
    expect(output).not_to include("Write the action's description")
    expect(Dir.children(destination)).to be_empty
  end

  it "puts back every file it wrote or changed when the catalogue step fails" do
    locale = destination.join("config/locales/actions.en.yml")
    catalogue = destination.join("config/actions.json")
    FileUtils.mkdir_p(locale.dirname)
    locale.write("en:\n  actions:\n    event/show:\n      description: Shows one.\n")
    catalogue.write("[]\n")
    generator = described_class.new(["Event::Update"], {"test_framework" => "rspec"}, destination_root: destination.to_s)
    allow(generator).to receive(:rails_command).with("actions:catalogue").and_return(false)
    $stdout = StringIO.new
    expect { generator.invoke_all }.to raise_error(Thor::Error, /actions:catalogue failed, so nothing was written/)
    expect(destination.join("app/actions/event/update_action.rb")).not_to exist
    expect(destination.join("spec/actions/event/update_action_spec.rb")).not_to exist
    expect(locale.read).to eq("en:\n  actions:\n    event/show:\n      description: Shows one.\n")
    expect(catalogue.read).to eq("[]\n")
  ensure
    $stdout = STDOUT
  end

  it "asks for no policy when the base class has no authorization adapter" do
    stub_const("OpenAction", Class.new(Saltbox::Actions::Base))
    with_settings(base_class: "OpenAction") do
      generate("Event::Archive", "--kind", "change")
      expect(destination.join("app/actions/event/archive_action.rb").read).to include("class Event::ArchiveAction < OpenAction")
    end
  end

  it "writes actions that pass the boot checks" do
    with_archive_rule
    generate("Event::Archive", "--kind", "change")
    source = destination.join("app/actions/event/archive_action.rb").read
    klass = Class.new(ApplicationAction) { define_singleton_method(:name) { "Event::ArchiveAction" } }
    klass.class_eval(source.lines[1..-2].join)
    expect(Saltbox::Actions::Registry.problems(klass)).to eq([])
  end
end
