require "generators/actions/approvals/approvals_generator"

RSpec.describe Saltbox::Actions::Generators::ApprovalsGenerator do
  let(:destination) { Pathname(Dir.mktmpdir("approvals-generator")) }

  after { FileUtils.remove_entry(destination) }

  def generate(*args, approvals: {user: "User"})
    allow(Saltbox::Actions.config).to receive(:approvals).and_return(approvals)
    capture = StringIO.new
    $stdout = capture
    described_class.start(args, destination_root: destination.to_s)
    capture.string
  ensure
    $stdout = STDOUT
  end

  def migration = destination.glob("db/migrate/*_create_saltbox_action_approvals.rb").sole.read

  it "is what `rails g actions:approvals` finds" do
    expect(Rails::Generators.find_by_namespace("actions:approvals")).to eq(described_class)
  end

  it "writes only the migration of the gem's table; the model is the gem's" do
    output = generate
    expect(destination.glob("**/*").select(&:file?).map { it.relative_path_from(destination).to_s }).to match([%r{\Adb/migrate/\d+_create_saltbox_action_approvals\.rb\z}])
    expect(migration).to include("class CreateSaltboxActionApprovals < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]")
    expect(migration).to include("create_table :saltbox_action_approvals do |t|")
    expect(migration).to include("t.references :user, null: false, foreign_key: {to_table: :users}\n")
    expect(migration).to include("t.references :connection\n")
    expect(migration).not_to include(":tenant")
    expect(migration).to include("t.json :arguments, null: false\n")
    expect(output).to include('config.approvals = {user: "User"}')
  end

  it "writes the columns Saltbox::Actions::Approval runs on, with the dummy app's tenant" do
    generate(approvals: {user: "User", tenant: "Org"})
    columns = migration.scan(/t\.(?:references|string|json|datetime) :(\w+)/).flatten.map { %w[tenant user connection].include?(it) ? "#{it}_id" : it }
    expect(columns + %w[id created_at updated_at]).to match_array(Saltbox::Actions::Approval.column_names)
  end

  it "points each foreign key at the table of the class config.approvals names, with the app's key type" do
    stub_const("Oauth::Connection", Class.new(ApplicationRecord) { self.table_name = "oauth_connections" })
    generate("--primary-key-type=uuid", approvals: {user: "Account", tenant: "Org", connection: "Oauth::Connection"})
    expect(migration).to include("create_table :saltbox_action_approvals, id: :uuid do |t|")
    expect(migration).to include("t.references :tenant, null: false, type: :uuid, foreign_key: {to_table: :orgs}\n")
    expect(migration).to include("t.references :user, null: false, type: :uuid, foreign_key: {to_table: :accounts}\n")
    expect(migration).to include("t.references :connection, type: :uuid, foreign_key: {to_table: :oauth_connections, on_delete: :cascade}\n")
  end
end
