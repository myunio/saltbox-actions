RSpec.describe Saltbox::Actions::Registry do
  def action(name, &body)
    Class.new(ApplicationAction) do
      define_singleton_method(:name) { name }
      class_eval(&body) if body
    end
  end

  def problems(klass) = described_class.problems(klass)

  it "loads every action under app/actions, sorted, with unique names" do
    expect(described_class.actions.map(&:action_name)).to eq(%w[cancel_event count_events create_event delete_event list_billing_events list_billing_invoices list_events
      postpone_event show_event show_event_notes update_event whoami])
  end

  it "takes an application_action.rb in any folder, such as a back office's base class, as shared code" do
    Dir.mktmpdir do |root|
      %w[admin/application_action.rb admin/application_action/scoping.rb admin/events/list_action.rb].each do |file|
        FileUtils.mkdir_p(File.dirname(File.join(root, file)))
        FileUtils.touch(File.join(root, file))
      end
      with_settings(action_paths: [root]) do
        expect(described_class.action_files).to eq([File.join(root, "admin/events/list_action.rb")])
      end
    end
  end

  it "finds the actions as the base class's subclasses when the folder holds other files too" do
    with_settings(strict_action_paths: false) do
      described_class.reset!
      expect(described_class.actions).to include(Events::UpdateAction, Reports::CountEventsAction, WhoamiAction)
    ensure
      described_class.reset!
    end
  end

  it "refuses a Rails verb, naming the one to use" do
    expect(problems(action("Events::DestroyAction"))).to eq(["destroy is spelled delete in actions: rename it Events::DeleteAction"])
  end

  it "refuses a kind on a verb whose kind is known, and an unknown verb with none" do
    expect(problems(action("Events::DeleteAction") { kind :change })).to include(/its kind is destructive: remove kind/)
    expect(problems(action("Events::ArchiveAction") { policy_rule :update? })).to include(/declare kind .* or add it with define_verb/)
  end

  it "takes the agents rule from the verb, and refuses a destructive action agents may run without asking" do
    expect(problems(action("Events::ShowAction"))).to be_empty
    expect(problems(action("Events::DeleteAction") { agents :allowed })).to include(/never agents :allowed/)
  end

  it "refuses an action inside its model's namespace, naming the plural one" do
    expect(problems(action("Event::ShowAction")))
      .to eq(["Event is a model: name its actions like controllers, in the plural namespace: Events::ShowAction in events/show_action.rb"])
  end

  it "refuses an attribute named like the member record's reader" do
    expect(problems(action("Events::ShowAction") { attribute :event, :string }))
      .to include("attribute event has the name of the reader for the event it works on: rename the attribute")
  end

  it "refuses a model whose record reader would replace a method every action has" do
    stub_const("Result", Class.new(ActiveRecord::Base) { self.table_name = "events" })
    expect(problems(action("Results::ShowAction")))
      .to include(a_string_starting_with("Saltbox::Actions::Rendering#result is a method every action has"))
  end

  it "gives a User member action its user reader, beside current_user, the person running it" do
    stub_const("User", Class.new(ActiveRecord::Base) { self.table_name = "events" })
    show = action("Users::ShowAction")
    expect(show.record_reader_conflict).to be_nil
    expect(problems(show)).not_to include(a_string_matching(/method every action has/))
    show.define_record_reader
    expect(show.instance_method(:user).owner).to be_a(Saltbox::Actions::Base::RecordReader)
    expect(show.instance_method(:current_user).owner).to eq(Saltbox::Actions::Base)
  end

  it "takes the record's id as a cli argument of an action that declares attribute :id" do
    archive = action("Events::ArchiveAction") do
      kind :change
      attribute :id
      policy_rule :update?
      cli "events archive", args: [:id]
    end
    expect(archive.declared_cli).to include(args: ["id"])
  end

  it "refuses a validation of a model field, which is not an attribute of the action" do
    expect(problems(action("Events::UpdateAction") { validates :title, presence: true }))
      .to include("validates title, which is not an attribute: the model's own validations check its fields, or declare it with attribute")
  end

  it "refuses validations whose schema would promise what they refuse" do
    expect(problems(action("Events::ExportAction") {
      attribute :format, :string
      validates :format, inclusion: {in: %i[csv json]}
      attribute :archived, :boolean
      validates :archived, presence: true
    })).to include("format is a string, and its inclusion lists symbols, so every value is refused: list strings",
      "archived is a boolean, and presence refuses false: validate inclusion: {in: [true, false]}")
  end

  it "refuses accepts under a policy that says which fields a person may set, and on an action with no model" do
    expect(problems(action("Events::UpdateAction") { accepts :title }))
      .to include("EventPolicy#permitted_attributes says which fields a person may set: remove accepts, so the policy is the one list")
    expect(problems(action("SummariseAction") {
      kind :read
      accepts :title
    })).to include("accepts names fields of the action's model, and it has none: declare model, or remove accepts")
  end

  it "refuses a longer name that names no policy rule, and a rule the policy lacks" do
    expect(problems(action("Events::ShowTotalsAction"))).to eq(["show totals says more than show: name the policy rule, policy_rule :show? or another"])
    expect(problems(action("Events::ArchiveAction") {
      kind :change
      policy_rule :archive?
    }))
      .to include("EventPolicy#archive? is missing: add it, or name another with policy_rule")
  end

  it "refuses an action under a name that is not a model, or whose model has no area" do
    expect(problems(action("Reports::ShowAction"))).to eq(["Reports names no model (Report is not one): declare model, or move the action"])
    stub_const("Venue", Class.new(ApplicationRecord) { self.table_name = "events" })
    stub_const("VenuePolicy", Class.new(EventPolicy))
    expect(problems(action("Venues::ShowAction"))).to include("no area maps Venue: add it to the app's areas")
  end

  it "names a namespace that is not a model before sorting by name, which needs the model" do
    stub_const("Admin::Customers", Module.new)
    stray = action("Admin::Customers::ExportAction")
    allow(described_class).to receive(:descendants).and_return([stray, Events::ListAction])
    with_settings(strict_action_paths: false) do
      described_class.reset!
      expect { described_class.actions }.to raise_error(ArgumentError, "Admin::Customers::ExportAction: Admin::Customers names no model (Admin::Customer is not one): declare model, or move the action")
    ensure
      described_class.reset!
    end
  end

  it "names both classes when two actions share a name" do
    upcoming = action("Events::ListUpcomingAction") {
      action_name "list_events"
      kind :read
      model Event
      policy_rule :index?
    }
    expect { described_class.validate!([upcoming, Events::ListAction]) }
      .to raise_error(ArgumentError, /Action names must be unique: list_events \(Events::ListAction, Events::ListUpcomingAction\)\. To fix: declare action_name/)
  end

  it "keeps a back-office action apart from the public one, by its outer namespace" do
    admin = action("Admin::Events::ListAction")
    expect(described_class.validate!([admin, Events::ListAction])).to be_nil
  end

  it "refuses two actions with one CLI command, or an alias that is another's command" do
    tally = action("Events::TallyAction") {
      kind :read
      policy_rule :index?
      cli "events tally", aliases: ["events list"]
    }
    expect { described_class.validate!([tally, Events::ListAction]) }
      .to raise_error(ArgumentError, /CLI commands must be unique: events list \(Events::ListAction, Events::TallyAction\)\. To fix: declare cli/)
  end

  it "runs the app's own checks beside the gem's" do
    Saltbox::Actions.config.check_action { |klass| klass.description ? [] : ["write a description"] }
    expect(problems(action("Events::PeekAction") {
      kind :read
      policy_rule :show?
    })).to eq(["write a description"])
  ensure
    Saltbox::Actions.config.action_checks.pop
  end

  it "versions every definition, and lists the definitions as the catalog file holds them" do
    expect(described_class.version).to match(/\A\h{16}\z/)
    expect(JSON.parse(described_class.catalog_json).pluck("name")).to eq(described_class.actions.map(&:action_name))
  end

  it "lists each action for a caller with whether they may run it" do
    entries = described_class.catalog(as_mcp(manager))
    expect(entries.find { it["name"] == "show_event_notes" }).to be_nil
    expect(entries.find { it["name"] == "delete_event" }).to include("runnable" => true, "agents" => "confirm", "kind" => "destructive")
    expect(described_class.catalog(as_read_only(manager)).pluck("kind").uniq).to eq(["read"])
  end
end
