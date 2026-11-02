RSpec.describe Saltbox::Actions::Registry do
  def action(name, &body)
    Class.new(ApplicationAction) do
      define_singleton_method(:name) { name }
      class_eval(&body) if body
    end
  end

  def problems(klass) = described_class.problems(klass)

  it "loads every action under app/actions, sorted, with unique names" do
    expect(described_class.actions.map(&:action_name)).to eq(%w[cancel_event count_events create_event delete_event list_billing_invoices list_events
      show_event show_event_notes update_event whoami])
  end

  it "finds the actions as the base class's subclasses when the folder holds other files too" do
    with_settings(every_file_an_action: false) do
      described_class.reset!
      expect(described_class.actions).to include(Event::UpdateAction, Reports::CountEventsAction, WhoamiAction)
    ensure
      described_class.reset!
    end
  end

  it "refuses a Rails verb, naming the one to use" do
    expect(problems(action("Event::DestroyAction") { connections :confirm })).to eq(["destroy is spelled delete in actions: rename it Event::DeleteAction"])
  end

  it "refuses a kind on a verb whose kind is known, and an unknown verb with none" do
    expect(problems(action("Event::DeleteAction") {
      connections :confirm
      kind :change
    })).to include(/its kind is destructive: remove kind/)
    expect(problems(action("Event::ArchiveAction") {
      connections :allowed
      authorize :update?
    })).to include(/declare kind/)
  end

  it "refuses an action without connections, and a destructive one agents may run without asking" do
    expect(problems(action("Event::ShowAction"))).to include("declare connections :allowed, :confirm or :never")
    expect(problems(action("Event::DeleteAction") { connections :allowed })).to include(/never connections :allowed/)
  end

  it "refuses a longer name that names no policy rule, and a rule the policy lacks" do
    expect(problems(action("Event::ShowTotalsAction") { connections :allowed })).to eq(["show totals says more than show: name the policy query, authorize :show? or another"])
    expect(problems(action("Event::ArchiveAction") {
      kind :change
      connections :allowed
      authorize :archive?
    }))
      .to include("EventPolicy#archive? is missing: add it, or authorize another query")
  end

  it "refuses an action under a name that is not a model, or whose model has no area" do
    expect(problems(action("Reports::ShowAction") { connections :allowed })).to eq(["Reports is not a model: declare model, or move the action"])
    stub_const("Venue", Class.new(ApplicationRecord) { self.table_name = "events" })
    stub_const("VenuePolicy", Class.new(EventPolicy))
    expect(problems(action("Venue::ShowAction") { connections :allowed })).to include("no area maps Venue: add it to the app's areas")
  end

  it "names a namespace that is not a model before sorting by name, which needs the model" do
    stub_const("Admin::Customer", Module.new)
    stray = action("Admin::Customer::ExportAction") { connections :allowed }
    allow(described_class).to receive(:descendants).and_return([stray, Event::ListAction])
    with_settings(every_file_an_action: false) do
      described_class.reset!
      expect { described_class.actions }.to raise_error(ArgumentError, "Admin::Customer::ExportAction: Admin::Customer is not a model: declare model, or move the action")
    ensure
      described_class.reset!
    end
  end

  it "names both classes when two actions share a name" do
    admin = action("Admin::Event::ListAction") {
      model Event
      connections :allowed
    }
    expect { described_class.validate!([admin, Event::ListAction]) }
      .to raise_error(ArgumentError, /Action names must be unique: list_events \(Admin::Event::ListAction, Event::ListAction\)\. To fix: declare action_name/)
  end

  it "refuses two actions with one CLI command, or an alias that is another's command" do
    tally = action("Event::TallyAction") {
      kind :read
      authorize :index?
      connections :allowed
      cli "events tally", aliases: ["events list"]
    }
    expect { described_class.validate!([tally, Event::ListAction]) }
      .to raise_error(ArgumentError, /CLI commands must be unique: events list \(Event::ListAction, Event::TallyAction\)\. To fix: declare cli/)
  end

  it "runs the app's own checks beside the gem's" do
    Saltbox::Actions.config.check_action { |klass| klass.description ? [] : ["write a description"] }
    expect(problems(action("Event::PeekAction") {
      kind :read
      connections :allowed
      authorize :show?
    })).to eq(["write a description"])
  ensure
    Saltbox::Actions.config.action_checks.pop
  end

  it "versions every definition, and lists the definitions as the catalogue file holds them" do
    expect(described_class.version).to match(/\A\h{16}\z/)
    expect(JSON.parse(described_class.catalogue_json).pluck("name")).to eq(described_class.actions.map(&:action_name))
  end

  it "lists each action for a caller with whether they may run it" do
    entries = described_class.catalogue(as_mcp(manager))
    expect(entries.find { it["name"] == "show_event_notes" }).to be_nil
    expect(entries.find { it["name"] == "delete_event" }).to include("runnable" => true, "connections" => "confirm", "kind" => "destructive")
    expect(described_class.catalogue(as_read_only(manager)).pluck("kind").uniq).to eq(["read"])
  end
end
