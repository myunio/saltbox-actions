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

  it "writes an update action that reads its member record, and its spec, from a plural or a singular resource" do
    output = generate("Events::Update")
    action = destination.join("app/actions/events/update_action.rb").read
    expect(action).to eq(<<~RUBY)
      class Events::UpdateAction < ApplicationAction
        def perform
          event.update!(permitted_attributes(event))
          render :show
        end
      end
    RUBY
    spec = destination.join("spec/actions/events/update_action_spec.rb").read
    expect(spec).to include("RSpec.describe Events::UpdateAction", "let(:arguments) { {id: event.id} }",
      %(it_behaves_like "refuses callers the action does not allow"), %(it_behaves_like "hides records the caller cannot see"))
    expect(spec).not_to include("unpermitted_account) {", "create(")
    expect(output).to include("write its description in the class", "Describe starts_on, capacity", "under actions.events.fields")
    generate("Event::Update", "--force")
    expect(destination.join("app/actions/events/update_action.rb").read).to eq(action)
  end

  it "declares no connections, leaving them to the verb" do
    generate("Events::Delete")
    action = destination.join("app/actions/events/delete_action.rb").read
    expect(action).to include("event.destroy!", "head :no_content")
    expect(action).not_to include("connections")
  end

  it "lists through the policy scope alone" do
    generate("Events::List")
    action = destination.join("app/actions/events/list_action.rb").read
    expect(action).to include("@events = policy_scope(Event)")
    expect(action).not_to include("authorize")
  end

  it "declares kind, id and the policy rule for a verb outside the table, and gives its spec the id" do
    with_archive_rule
    generate("Events::Archive", "--kind", "destructive")
    action = destination.join("app/actions/events/archive_action.rb").read
    expect(action).to include("kind :destructive", "attribute :id", "policy_rule :archive?", "render :show")
    expect(destination.join("spec/actions/events/archive_action_spec.rb").read).to include("let(:arguments) { {id: event.id} }")
  end

  it "knows a verb the app adds with define_verb" do
    stub_const("EventPolicy", Class.new(EventPolicy) { def postpone? = create? })
    generate("Events::Postpone")
    expect(destination.join("app/actions/events/postpone_action.rb").read).not_to include("kind", "attribute :id", "policy_rule")
  end

  it "points a list action at its model's summary only when the model has none" do
    expect(generate("Events::List")).not_to include("summary Event")
    allow(ApplicationAction).to receive(:model_summaries).and_return({})
    expect(generate("Events::List", "--force")).to include("Agents get each event's full view", "`summary Event, :id, ...` in ApplicationAction")
  end

  it "refuses a Rails verb, an unknown verb without a kind, and a name that is not a model" do
    expect { described_class.new(["Events::Destroy"]).check }.to raise_error(Thor::Error, "destroy is spelled delete in actions: bin/rails g action Events::Delete")
    expect { described_class.new(["Events::Archive"]).check }.to raise_error(Thor::Error, /pass --kind .* or add it with define_verb/)
    expect { described_class.new(["Reports::Show"]).check }.to raise_error(Thor::Error, /Reports names no model \(Report is not one\)/)
  end

  it "writes nothing when the action would fail the boot check, and prints the fix, not the next steps" do
    output = generate_failing("Events::Archive", "--kind", "change")
    expect(output).to include("Events::ArchiveAction would not pass rails actions:check, so nothing was written",
      "EventPolicy#archive? is missing: add it, or name another with policy_rule")
    expect(output).not_to include("write its description")
    expect(Dir.children(destination)).to be_empty
  end

  it "puts back every file it wrote or changed when the catalogue step fails" do
    catalogue = destination.join("config/actions.json")
    FileUtils.mkdir_p(catalogue.dirname)
    catalogue.write("[]\n")
    generator = described_class.new(["Events::Update"], {"test_framework" => "rspec"}, destination_root: destination.to_s)
    allow(generator).to receive(:rails_command).with("actions:catalogue").and_return(false)
    $stdout = StringIO.new
    expect { generator.invoke_all }.to raise_error(Thor::Error, /actions:catalogue failed, so nothing was written/)
    expect(destination.join("app/actions/events/update_action.rb")).not_to exist
    expect(destination.join("spec/actions/events/update_action_spec.rb")).not_to exist
    expect(catalogue.read).to eq("[]\n")
  ensure
    $stdout = STDOUT
  end

  it "asks for no policy when the base class has no authorization adapter, and lists an update's fields with accepts" do
    stub_const("OpenAction", Class.new(Saltbox::Actions::Base))
    with_settings(base_class: "OpenAction") do
      generate("Events::Archive", "--kind", "change")
      expect(destination.join("app/actions/events/archive_action.rb").read).to include("class Events::ArchiveAction < OpenAction")
      generate("Events::Update")
      expect(destination.join("app/actions/events/update_action.rb").read)
        .to include("accepts :org_id, :title, :starts_on, :capacity, :price, :featured, :doors_open_at, :status, :notes, :parent")
    end
  end

  it "writes actions that pass the boot checks" do
    with_archive_rule
    generate("Events::Archive", "--kind", "change")
    source = destination.join("app/actions/events/archive_action.rb").read
    klass = Class.new(ApplicationAction) { define_singleton_method(:name) { "Events::ArchiveAction" } }
    klass.class_eval(source.lines[1..-2].join)
    expect(Saltbox::Actions::Registry.problems(klass)).to eq([])
  end
end
