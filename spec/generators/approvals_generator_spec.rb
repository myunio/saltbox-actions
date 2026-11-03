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
    expect(model).to include("acts_as_tenant :org")
    expect(migration).to include("t.references :account, null: false, foreign_key: true, type: :uuid\n")
    expect(migration).to include("t.references :connection, type: :uuid, foreign_key: {to_table: :oauth_connections, on_delete: :cascade}\n")
    expect(migration).to include("%i[account_id action_name confirms arguments_digest]")
    expect(model).to include("self.approver = :account")
    expect(model).to include("belongs_to :account")
  end
end
