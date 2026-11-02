# Every action name the README and CHANGELOG give, run against the code, so
# the two cannot drift: each example's words must still be in its file, and
# the class must still give the name and policy they state.
RSpec.describe "Names in the README and CHANGELOG" do
  docs = %w[README.md CHANGELOG.md].to_h { [it, File.read(File.expand_path("../../../#{it}", __dir__))] }
  said = docs.transform_values(&:squish)

  def model_named(name) = name.safe_constantize || stub_const(name, Class.new(ApplicationRecord))

  def action(name, parent: ApplicationAction, model: nil, namespace: nil, declare: {})
    Class.new(parent) do
      define_singleton_method(:name) { name }
      define_singleton_method(:action_namespace) { namespace || nil } unless namespace.nil?
      self.model(model) if model
      declare.each { |declaration, value| public_send(declaration, value) }
    end
  end

  # Each example: the file, its words, the action as the words describe it,
  # and what the class gives. model: is the model the words name, declared
  # when declared: true; parent: is a base class the action inherits from.
  # An action with no model names, in asks:, the model its perform
  # authorizes and the policy that asks.
  examples = [
    {doc: "README.md", says: "`Events::UpdateAction` works on `Event`, asks the policy's `update?` rule, and is named `update_event`",
     action: "Events::UpdateAction", model: "Event", gives: {action_name: "update_event", expected_policy_name: "EventPolicy", policy_query: :update?}},
    {doc: "README.md", says: "`Tasks::List`, `Tasks::Show`, `Tasks::Create`, `Tasks::Update` and `Tasks::Delete`, named `list_tasks`, `show_task` and so on",
     action: "Tasks::ListAction", model: "Task", gives: {action_name: "list_tasks"}},
    {doc: "README.md", says: "the walkthrough above, `TaskPolicy` lets it list tasks", action: "Tasks::ListAction", model: "Task", gives: {expected_policy_name: "TaskPolicy"}},
    {doc: "README.md", says: "named `list_tasks`, `show_task` and so on", action: "Tasks::ShowAction", model: "Task", gives: {action_name: "show_task"}},
    {doc: "README.md", says: "So `Events::ListAction` is named `list_events`", action: "Events::ListAction", model: "Event", gives: {action_name: "list_events"}},
    {doc: "README.md", says: "`Events::ShowNotesAction` is named `show_event_notes`", action: "Events::ShowNotesAction", model: "Event", gives: {action_name: "show_event_notes"}},
    {doc: "README.md", says: "`Admin::Events::ListAction`, takes that module into its name: `list_admin_events`, with the CLI command `admin-events list`. " \
      "It never collides with `Events::ListAction`, and it asks `Admin::EventPolicy`",
     action: "Admin::Events::ListAction", model: "Event", gives: {action_name: "list_admin_events", cli_command: %w[admin-events list], expected_policy_name: "Admin::EventPolicy"}},
    {doc: "README.md", says: "If everyone `AttendeePolicy` allows may run it, declare `policy_namespace false` to ask that policy; otherwise add `Events::AttendeePolicy`. " \
      "The name stays `list_events_attendees`.",
     action: "Events::Attendees::ListAction", model: "Attendee", declare: {policy_namespace: false}, gives: {action_name: "list_events_attendees", expected_policy_name: "AttendeePolicy"}},
    {doc: "README.md", says: "`Admin::Reports::ExportAction` with `model Customer` is named `export_admin_reports_customers` and asks `Admin::Reports::CustomerPolicy`.",
     action: "Admin::Reports::ExportAction", model: "Customer", declared: true, gives: {action_name: "export_admin_reports_customers", expected_policy_name: "Admin::Reports::CustomerPolicy"}},
    {doc: "README.md", says: "`Billing::Invoices::ListAction` is named `list_billing_invoices`, with the CLI command `billing-invoices list`.",
     action: "Billing::Invoices::ListAction", model: "Billing::Invoice", namespace: "billing", gives: {action_name: "list_billing_invoices", cli_command: %w[billing-invoices list]}},
    {doc: "README.md", says: "Without `namespace:`, names come from the class, and the CLI command leaves the module out (`invoices list`).",
     action: "Billing::Invoices::ListAction", model: "Billing::Invoice", namespace: false, gives: {cli_command: %w[invoices list]}},
    {doc: "README.md", says: "A model in an engine that is not isolated keeps its module in its name, so a namespace would be added to it (`list_billing_billing_invoices`).",
     action: "Billing::Invoices::ListAction", model: "Billing::Invoice", isolated: false, declared: true, namespace: "billing", gives: {action_name: "list_billing_billing_invoices"}},
    {doc: "README.md", says: "`Events::UpdateAction` asks `EventPolicy#update?`, and its input takes the fields from the policy's `permitted_attributes`.",
     action: "Events::UpdateAction", model: "Event", gives: {expected_policy_name: "EventPolicy", policy_query: :update?}},
    {doc: "README.md", says: "`Admin::Events::UpdateAction` asks `Admin::EventPolicy#update?`: before any record loads",
     action: "Admin::Events::UpdateAction", model: "Event", gives: {expected_policy_name: "Admin::EventPolicy", policy_query: :update?}},
    {doc: "README.md", says: "`Admin::CountProjectsAction`'s `authorize Project` and `policy_scope(Project)` ask `Admin::ProjectPolicy`",
     action: "Admin::CountProjectsAction", declare: {action_name: "count_admin_projects", kind: :read}, asks: %w[Project Admin::ProjectPolicy]},
    {doc: "README.md", says: "a top-level `CountProjectsAction`'s ask `ProjectPolicy`",
     action: "CountProjectsAction", declare: {action_name: "count_projects", kind: :read}, asks: %w[Project ProjectPolicy]},
    {doc: "README.md", says: "An action with a declared name that works on one model declares `model`, so the model's own modules are left out: " \
      "without it, `Billing::Invoices::CountAction` asks `Billing::Invoices::Billing::InvoicePolicy`.",
     action: "Billing::Invoices::CountAction", declare: {action_name: "count_invoices", kind: :read}, asks: %w[Billing::Invoice Billing::Invoices::Billing::InvoicePolicy]},
    {doc: "README.md", says: "`Admin::Events::ListAllAction < Events::ListAllAction`, whose parent declares `policy_namespace false`, asks `Admin::EventPolicy`",
     action: "Admin::Events::ListAllAction", model: "Event", parent: ["Events::ListAllAction", false], gives: {action_name: "list_admin_events_all", expected_policy_name: "Admin::EventPolicy"}},
    {doc: "README.md", says: "with `policy_namespace :staff` in `ApplicationAction`, `Events::ListAction` asks `Staff::EventPolicy`",
     action: "Events::ListAction", model: "Event", parent: ["ApplicationAction", :staff], gives: {expected_policy_name: "Staff::EventPolicy"}},
    {doc: "README.md", says: "`Admin::Events::ListAction` asks `Staff::Admin::EventPolicy`",
     action: "Admin::Events::ListAction", model: "Event", parent: ["ApplicationAction", :staff], gives: {expected_policy_name: "Staff::Admin::EventPolicy"}},
    {doc: "README.md", says: "with `policy_namespace :staff` in a base class `Admin::ApplicationAction`, `Admin::Events::ListAction` asks `Staff::EventPolicy`",
     action: "Admin::Events::ListAction", model: "Event", parent: ["Admin::ApplicationAction", :staff], gives: {expected_policy_name: "Staff::EventPolicy"}},
    {doc: "README.md", says: "and `Admin::Reports::ExportAction` on `Event` asks `Staff::Reports::EventPolicy`",
     action: "Admin::Reports::ExportAction", model: "Event", declared: true, parent: ["Admin::ApplicationAction", :staff], gives: {expected_policy_name: "Staff::Reports::EventPolicy"}},
    {doc: "CHANGELOG.md", says: "`Admin::Projects::ListAction` asks `Admin::ProjectPolicy`",
     action: "Admin::Projects::ListAction", model: "Project", gives: {expected_policy_name: "Admin::ProjectPolicy"}},
    {doc: "CHANGELOG.md", says: "`policy_namespace :staff` in a base class makes `Admin::Projects::ListAction` ask `Staff::Admin::ProjectPolicy`",
     action: "Admin::Projects::ListAction", model: "Project", parent: ["ApplicationAction", :staff], gives: {expected_policy_name: "Staff::Admin::ProjectPolicy"}},
    {doc: "CHANGELOG.md", says: "the same in `Admin::ApplicationAction` makes it ask `Staff::ProjectPolicy`",
     action: "Admin::Projects::ListAction", model: "Project", parent: ["Admin::ApplicationAction", :staff], gives: {expected_policy_name: "Staff::ProjectPolicy"}},
    {doc: "CHANGELOG.md", says: "`Admin::ExportAction` on `Project` is `export_admin_projects` and asks `Admin::ProjectPolicy`",
     action: "Admin::ExportAction", model: "Project", declared: true, gives: {action_name: "export_admin_projects", expected_policy_name: "Admin::ProjectPolicy"}},
    {doc: "CHANGELOG.md", says: "`Reports::ExportAction` on `Customer` is `export_reports_customers` and asks `Reports::CustomerPolicy`",
     action: "Reports::ExportAction", model: "Customer", declared: true, gives: {action_name: "export_reports_customers", expected_policy_name: "Reports::CustomerPolicy"}},
    {doc: "CHANGELOG.md", says: "`Events::Attendees::ListAction` on `Attendee` is `list_events_attendees` and asks `Events::AttendeePolicy`",
     action: "Events::Attendees::ListAction", model: "Attendee", gives: {action_name: "list_events_attendees", expected_policy_name: "Events::AttendeePolicy"}},
    {doc: "CHANGELOG.md", says: "`Crm::Organizations::ListAction` on a top-level `Organization` is `list_crm_organizations` and asks `Crm::OrganizationPolicy`",
     action: "Crm::Organizations::ListAction", model: "Organization", gives: {action_name: "list_crm_organizations", expected_policy_name: "Crm::OrganizationPolicy"}},
    {doc: "CHANGELOG.md", says: "it is `list_admin_billing_invoices` and asks `Admin::Billing::InvoicePolicy`",
     action: "Admin::Billing::Invoices::ListAction", model: "Billing::Invoice", gives: {action_name: "list_admin_billing_invoices", expected_policy_name: "Admin::Billing::InvoicePolicy"}},
    {doc: "CHANGELOG.md", says: "`Billing::Projects::ListAction` in a folder named `billing` is `list_billing_projects`, and asks `Billing::ProjectPolicy`",
     action: "Billing::Projects::ListAction", model: "Project", namespace: "billing", gives: {action_name: "list_billing_projects", expected_policy_name: "Billing::ProjectPolicy"}},
    {doc: "CHANGELOG.md", says: "`Admin::Projects::ListAction` is `list_admin_projects`, with the CLI command `admin-projects list` and the title \"List admin projects\"",
     action: "Admin::Projects::ListAction", model: "Project", gives: {action_name: "list_admin_projects", cli_command: %w[admin-projects list], title: "List admin projects"}},
    {doc: "CHANGELOG.md", says: "`show_admin_project`", action: "Admin::Projects::ShowAction", model: "Project", gives: {action_name: "show_admin_project"}},
    {doc: "CHANGELOG.md", says: "is refused as \"update_note does not take user_id.", action: "Notes::UpdateAction", model: "Note", gives: {action_name: "update_note"}},
    {doc: "CHANGELOG.md", says: "`Admin::CountProjectsAction`, with a declared name, asked `ProjectPolicy` in its own `authorize Project` and `policy_scope(Project)`; " \
      "it asks `Admin::ProjectPolicy`",
     action: "Admin::CountProjectsAction", declare: {action_name: "count_admin_projects", kind: :read}, asks: %w[Project Admin::ProjectPolicy]},
    {doc: "CHANGELOG.md", says: "`Events::TallyAction` with no model asks `Events::EventPolicy`",
     action: "Events::TallyAction", declare: {action_name: "tally_events", kind: :read}, asks: %w[Event Events::EventPolicy]},
    {doc: "CHANGELOG.md", says: "it is still `update_event`", action: "Events::UpdateAction", model: "Event", gives: {action_name: "update_event"}}
  ]

  # The README's naming table: Action | Model | Name | Policy. Every row of
  # it is an example, so a row written another way fails here.
  table = docs["README.md"][/^\| Action \| Model \| Name \| Policy \|\n\|[-|]+\|\n((?:\|.*\n)+)/, 1].to_s.lines
  table_rows = table.grep(/^\| `(\w+(?:::\w+)*Action)` \| `([\w:]+)`( \(declared\))? \| `(\w+)` \| `([\w:]+)` \|$/)
  table_rows.each do |row|
    klass, model, declared, name, policy = row.match(/^\| `([\w:]+)` \| `([\w:]+)`( \(declared\))? \| `(\w+)` \| `([\w:]+)` \|$/).captures
    examples << {doc: "README.md", says: row.chomp, action: klass, model:, declared: !!declared, gives: {action_name: name, expected_policy_name: policy}}
  end

  it "reads every row of the README's naming table" do
    expect(table.size).to be > 0
    expect(table - table_rows).to eq([])
  end

  # A model in an engine that is not isolated: its name keeps its module.
  def unisolated(name) = Class.new(ApplicationRecord) { define_singleton_method(:name) { name } }.tap { |model| model.define_singleton_method(:model_name) { ActiveModel::Name.new(model) } }

  examples.each do |example|
    it "gives what #{example[:doc]} says: #{example[:says].truncate(90)}" do
      expect(said.fetch(example[:doc])).to include(example[:says].squish)
      model = (example[:isolated] == false) ? unisolated(example[:model]) : example[:model]&.then { model_named(it) }
      parent = example[:parent]&.then { |name, namespace| action(name).tap { it.policy_namespace(namespace) } } || ApplicationAction
      built = action(example[:action], parent:, model: (model if example[:declared]), namespace: example[:namespace], declare: example[:declare] || {})
      expect(built.model).to eq(model)
      expect(built).to have_attributes(example[:gives]) if example[:gives]
      example[:asks]&.then { |authorized, policy| expect(built.expected_policy_name(model_named(authorized))).to eq(policy) }
    end
  end

  # A name in backticks, quotes or a path; file names (update_action.rb) and
  # Active Record methods (update_all) are not action names.
  it "has an example here for each action name the README and CHANGELOG give" do
    named = docs.values.join.scan(/[`"\/]((?:#{Saltbox::Actions::Naming::VERBS.keys.join("|")})_[a-z_]+)\b/).flatten.uniq
    named = named.grep_v(/_action(_spec|_test)?\z/) - %w[update_all delete_all insert_all update_column]
    expect(named - examples.filter_map { it.dig(:gives, :action_name) }).to eq([])
  end

  # A declared name starts with any word, so it is checked against the
  # dummy app's actions.
  it "gives each name the README and CHANGELOG declare with action_name to an action of the dummy app" do
    declared = docs.values.join.scan(/action_name[ (]["':](\w+)/).flatten.uniq
    expect(declared).not_to be_empty
    expect(declared - Saltbox::Actions::Registry.actions.map(&:action_name)).to eq([])
  end

  # Every policy the prose names, outside code samples: Admin::EventPolicy,
  # or Admin::EventPolicy#update? with its rule.
  it "has an example here for each policy the README and CHANGELOG name" do
    prose = docs.values.map { it.gsub(/^```.*?^```/m, "") }.join
    named = prose.scan(/`((?:[A-Z]\w*::)*[A-Z]\w*Policy(?:#\w+\?)?)`/).flatten.uniq - ["Saltbox::Actions::Authorization::ActionPolicy"]
    given = examples.flat_map do |example|
      policy = example.dig(:gives, :expected_policy_name) || example[:asks]&.last
      [policy, example.dig(:gives, :policy_query)&.then { "#{policy}##{it}" }]
    end
    expect(named - given.compact).to eq([])
  end
end
