require "generators/actions/approvals/approvals_generator"

RSpec.describe Saltbox::Actions::Generators::ApprovalsGenerator do
  let(:destination) { Pathname(Dir.mktmpdir("approvals-generator")) }

  after { FileUtils.remove_entry(destination) }

  def generate(*args)
    capture = StringIO.new
    $stdout = capture
    described_class.start(args, destination_root: destination.to_s)
    capture.string
  ensure
    $stdout = STDOUT
  end

  def migration = destination.glob("db/migrate/*_create_action_approvals.rb").sole.read

  def model = destination.join("app/models/action_approval.rb").read

  it "is what `rails g actions:approvals` finds" do
    expect(Rails::Generators.find_by_namespace("actions:approvals")).to eq(described_class)
  end

  it "writes the table and a model that includes the adapter, for an app of users" do
    output = generate
    expect(migration).to include("class CreateActionApprovals < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]")
    expect(migration).to include("create_table :action_approvals do |t|")
    expect(migration).to include("t.references :user, null: false, foreign_key: true\n")
    expect(migration).to include("t.references :connection\n")
    expect(migration).to include("t.json :arguments, null: false\n")
    expect(migration).not_to include("t.references :org")
    expect(migration).to include("%i[user_id action_name confirms arguments_digest]")
    expect(model).to include("include Saltbox::Actions::Adapters::Confirmation::Approvals")
    expect(model).to include("belongs_to :user")
    expect(model).not_to include("self.approver")
    expect(output).to include("ActionApproval.redeem!(invocation, action)")
  end

  it "writes the columns the dummy app's approvals run on" do
    generate
    columns = migration.scan(/t\.(?:references|string|json|datetime) :(\w+)/).flatten.map { %w[user connection].include?(it) ? "#{it}_id" : it }
    expect(columns + %w[id created_at updated_at]).to match_array(ActionApproval.column_names)
  end

  it "names the approver, the tenant, the connections table and the key type it is given" do
    generate("--approver=account", "--tenant=org", "--connections=oauth_connections", "--primary-key-type=uuid")
    expect(migration).to include("create_table :action_approvals, id: :uuid do |t|")
    expect(migration).to include("t.references :org, null: false, foreign_key: true, type: :uuid\n")
    expect(migration).to include("t.references :account, null: false, foreign_key: true, type: :uuid\n")
    expect(migration).to include("t.references :connection, type: :uuid, foreign_key: {to_table: :oauth_connections, on_delete: :cascade}\n")
    expect(migration).to include("%i[account_id action_name confirms arguments_digest]")
    expect(model).to include("self.approver = :account")
    expect(model).to include("belongs_to :account")
  end

  it "scopes the model to the current tenant with acts_as_tenant, when the app has it" do
    require "acts_as_tenant"
    generate("--tenant=org")
    connection = ActiveRecord::Base.connection
    connection.create_table(:orgs, force: true)
    connection.create_table(:users, force: true)
    ActiveRecord::Migration.suppress_messages do
      eval(migration.sub("CreateActionApprovals", "CreateTenantApprovals").gsub(":action_approvals", ":tenant_approvals"), binding, __FILE__, __LINE__) # standard:disable Security/Eval
      CreateTenantApprovals.migrate(:up)
    end
    stub_const("Org", Class.new(ApplicationRecord) { self.table_name = "orgs" })
    approvals = Class.new(ApplicationRecord) { self.table_name = "tenant_approvals" }
    stub_const("TenantApproval", approvals)
    approvals.class_eval(model[/^class ActionApproval < ApplicationRecord\n(.*)^end/m, 1])
    ours, theirs = Org.create!, Org.create!
    user_id = connection.insert("INSERT INTO users DEFAULT VALUES")
    row = {user_id:, surface: "mcp", action_name: "cancel_event", confirms: "cancel_event", arguments: {}, arguments_digest: "d",
           expires_at: 1.hour.from_now, created_at: Time.current, updated_at: Time.current}
    approvals.insert_all([row.merge(org_id: ours.id), row.merge(org_id: theirs.id)])

    ActsAsTenant.with_tenant(ours) { expect(approvals.pending.pluck(:org_id)).to eq([ours.id]) }
    ActsAsTenant.with_tenant(theirs) { expect(approvals.pending.pluck(:org_id)).to eq([theirs.id]) }
  ensure
    %i[tenant_approvals users orgs].each { connection&.drop_table(it, if_exists: true) }
  end

  it "has the model belong to the tenant without acts_as_tenant" do
    hide_const("ActsAsTenant")
    generate("--tenant=org")
    expect(model).to include("belongs_to :org")
    expect(model).not_to include("acts_as_tenant")
  end
end
