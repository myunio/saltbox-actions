RSpec.describe Saltbox::Actions::Naming do
  it "works out each action's name, CLI command, kind, id and policy rule from its class name" do
    expect(Events::UpdateAction).to have_attributes(action_name: "update_event", cli_command: %w[events update],
      kind: :change, takes_id?: true, policy_query: :update?, model: Event, area: "events", idempotent?: true)
    expect(Events::ListAction).to have_attributes(action_name: "list_events", kind: :read, takes_id?: false, policy_query: :index?)
    expect(Events::DeleteAction).to have_attributes(action_name: "delete_event", kind: :destructive, policy_query: :destroy?)
    expect(Events::ShowNotesAction).to have_attributes(action_name: "show_event_notes", policy_query: :view_notes?)
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
      cli_command: %w[admin-events list], title: "List admin events", policy_query: :index?, model: Event)
    expect(action("Admin::Events::ShowNotesAction")).to have_attributes(action_name: "show_admin_event_notes")
    expect(action("Admin::Customers::ExportAction") { model Event }).to have_attributes(action_name: "export_admin_events")
    expect(action("Admin::Billing::Invoices::ListAction") { model Billing::Invoice }).to have_attributes(outer_namespace: ["admin"], action_name: "list_admin_billing_invoices")
    expect(action("Billing::Invoices::ListAction")).to have_attributes(outer_namespace: [], action_name: "list_billing_invoices")
    expect(action("Reports::CountAction") { model Event }).to have_attributes(outer_namespace: [], action_name: "count_event")
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

  it "adds an app's own verbs, each with its kind, member or collection, idempotence and connections rule" do
    base = Class.new(ApplicationAction) do
      define_verb :archive, :restore, kind: :change, on: :member, idempotent: true
      define_verb :void, kind: :destructive, on: :member, connections: :never
      define_verb :import, kind: :change
    end
    expect(action("Events::ArchiveAction", base:)).to have_attributes(kind: :change, takes_id?: true, idempotent?: true, connections: :allowed)
    expect(action("Events::VoidAction", base:)).to have_attributes(kind: :destructive, connections: :never, policy_query: :void?)
    expect(action("Events::ImportAction", base:)).to have_attributes(kind: :change, takes_id?: false, idempotent?: false)
    expect(action("Events::ArchiveAction")).to have_attributes(kind: nil)
    expect(action("Events::DeleteAction", base:) { idempotent false }.idempotent?).to be(false)
    expect { base.define_verb :destroy, kind: :destructive }.to raise_error(ArgumentError, /destroy is spelled delete/)
    expect { base.define_verb :tidy, kind: :sweep }.to raise_error(ArgumentError, /kind is :read, :change or :destructive/)
    expect { base.define_verb :tidy, kind: :change, on: :item }.to raise_error(ArgumentError, /on is :member or :collection/)
  end
end
