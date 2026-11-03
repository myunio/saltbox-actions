RSpec.describe Saltbox::Actions::Naming do
  it "works out each action's name, CLI command, kind, id and policy rule from its class name" do
    expect(Events::UpdateAction).to have_attributes(action_name: "update_event", cli_command: %w[events update],
      kind: :change, takes_id?: true, policy_rule: :update?, model: Event, area: "events", idempotent?: true)
    expect(Events::ListAction).to have_attributes(action_name: "list_events", kind: :read, takes_id?: false, policy_rule: :index?)
    expect(Events::DeleteAction).to have_attributes(action_name: "delete_event", kind: :destructive, policy_rule: :destroy?)
    expect(Events::ShowNotesAction).to have_attributes(action_name: "show_event_notes", policy_rule: :view_notes?)
    expect(WhoamiAction).to have_attributes(action_name: "whoami", model: nil, kind: :read, cli_command: ["whoami"])
  end

  it "takes titles and descriptions from the locale file, building a title when it has none" do
    expect(Events::ListAction.title).to eq("List events")
    expect(Events::ShowNotesAction.title).to eq("Read an event's private notes")
    expect(Events::ListAction.description).to eq("Lists the events the person can see, newest first.")
    expect(Events::ListAction.field_description("status")).to eq("Only events with this status.")
    expect(Events::UpdateAction.field_description("id")).to eq("The record's id.")
  end

  def action(name, base: ApplicationAction, &body)
    Class.new(base) do
      define_singleton_method(:name) { name }
      class_eval(&body) if body
    end
  end

  it "finds the model by singularizing the namespace, walking out of it as wrap_parameters does" do
    expect(action("Admin::Events::ShowAction").model).to eq(Event)
    expect(action("Billing::Invoices::ListAction").model).to eq(Billing::Invoice)
    expect(action("Reports::ShowAction").model).to be_nil
    expect(action("Reports::ShowAction") { model Event }.model).to eq(Event)
  end

  it "names an action in a module its model is not in with that module, as a back office's controllers are" do
    expect(action("Admin::Events::ListAction")).to have_attributes(outer_namespace: ["admin"], action_name: "list_admin_events",
      cli_command: %w[admin-events list], title: "List admin events", policy_rule: :index?, model: Event)
    expect(action("Admin::Events::ShowNotesAction")).to have_attributes(action_name: "show_admin_event_notes")
    expect(action("Admin::Billing::Invoices::ListAction") { model Billing::Invoice }).to have_attributes(outer_namespace: ["admin"], action_name: "list_admin_billing_invoices")
    expect(action("Billing::Invoices::ListAction")).to have_attributes(outer_namespace: [], action_name: "list_billing_invoices")
  end

  it "counts a single module that does not name the model as one the model is not in" do
    expect(action("Admin::ExportAction") { model Event }).to have_attributes(outer_namespace: ["admin"], action_name: "export_admin_events",
      cli_command: %w[admin-events export], title: "Export admin events")
    expect(action("Reports::CountAction") { model Event }).to have_attributes(outer_namespace: ["reports"], action_name: "count_reports_event")
    expect(action("Admin::Customers::ExportAction") { model Event }).to have_attributes(outer_namespace: %w[admin customers],
      action_name: "export_admin_customers_events")
    expect(action("Events::Invoices::ListAction") { model Billing::Invoice }).to have_attributes(outer_namespace: ["events"],
      action_name: "list_events_billing_invoices")
  end

  it "finds a model in a module further in when the outer one has none" do
    expect(action("Admin::Billing::Invoices::ListAction")).to have_attributes(model: Billing::Invoice, outer_namespace: ["admin"],
      action_name: "list_admin_billing_invoices")
    stub_const("Invoice", Class.new)
    expect(action("Admin::Billing::Invoices::ListAction").model).to eq(Billing::Invoice)
    stub_const("Admin::Invoice", Class.new)
    expect(action("Admin::Billing::Invoices::ListAction").model).to eq(Admin::Invoice)
  end

  it "lets the locale file's title and description win over the class's, as Action Mailer's subject does" do
    postpone = action("Events::PostponeAction") do
      title "Move an event"
      description "Moves an event."
    end
    expect(postpone).to have_attributes(title: "Move an event", description: "Moves an event.")
    I18n.backend.store_translations(:en, actions: {"events/postpone": {title: "Postpone an event", description: "Moves an event later."}})
    expect(postpone).to have_attributes(title: "Postpone an event", description: "Moves an event later.")
  ensure
    I18n.reload!
  end

  it "describes a field from the action's locale entry, then its resource's, then the attribute, then the shared one" do
    renamed = action("Events::RenameAction") do
      kind :change
      policy_rule :update?
      attribute :title, :string, description: "The new name"
      attribute :id
    end
    expect(renamed.field_description("title")).to eq("The event's name.")
    expect(renamed.field_description("id")).to eq("The record's id.")
    plain = action("Venues::RenameAction") do
      kind :change
      attribute :title, :string, description: "The new name"
    end
    expect(plain.field_description("title")).to eq("The new name")
  end

  it "starts every app with the five verbs every app has, and no domain verbs" do
    expect(Saltbox::Actions::Base.verbs.keys).to eq(%w[list show create update delete])
    expect(Class.new(Saltbox::Actions::Base) { def self.name = "Events::PublishAction" }.kind).to be_nil
  end

  it "adds an app's own verbs, each with its kind, member or collection, idempotence and agents rule" do
    base = Class.new(ApplicationAction) do
      define_verb :archive, :restore, kind: :change, on: :member, idempotent: true
      define_verb :void, kind: :destructive, on: :member, agents: :never
      define_verb :import, kind: :change
    end
    expect(action("Events::ArchiveAction", base:)).to have_attributes(kind: :change, takes_id?: true, idempotent?: true, agents: :allowed)
    expect(action("Events::VoidAction", base:)).to have_attributes(kind: :destructive, agents: :never, policy_rule: :void?)
    expect(action("Events::ImportAction", base:)).to have_attributes(kind: :change, takes_id?: false, idempotent?: false)
    expect(action("Events::ArchiveAction")).to have_attributes(kind: nil)
    expect(action("Events::DeleteAction", base:) { idempotent false }.idempotent?).to be(false)
    expect { base.define_verb :destroy, kind: :destructive }.to raise_error(ArgumentError, /destroy is spelled delete/)
    expect { base.define_verb :tidy, kind: :sweep }.to raise_error(ArgumentError, /kind is :read, :change or :destructive/)
    expect { base.define_verb :tidy, kind: :change, on: :item }.to raise_error(ArgumentError, /on is :member or :collection/)
  end

  it "names an app's collection verb with the model's plural when it is defined plural, and with the singular otherwise" do
    base = Class.new(Saltbox::Actions::Base) do
      define_verb :export, kind: :read, plural: true
      define_verb :import, kind: :change
    end
    expect(action("Events::ExportAction", base:)).to have_attributes(action_name: "export_events", title: "Export events", kind: :read)
    expect(action("Events::ImportAction", base:)).to have_attributes(action_name: "import_event", title: "Import event")
    expect(action("Events::ExportAction", base: Class.new(Saltbox::Actions::Base)).kind).to be_nil
    expect { base.define_verb :archive, kind: :change, on: :member, plural: true }.to raise_error(ArgumentError, /plural is for a verb on: :collection/)
  end
end
