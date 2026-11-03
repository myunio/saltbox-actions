require "open3"

# Each example boots the dummy app in a process of its own, with eager
# loading on and the database unreachable (spec/boot_without_database.rb):
# its path runs through this file, so SQLite can neither open nor create it.
RSpec.describe "Booting without a database" do
  def boot(*arguments, database: "#{__FILE__}/app.sqlite3")
    Open3.capture2e({"DATABASE_URL" => "sqlite3:#{database}"},
      RbConfig.ruby, "spec/boot_without_database.rb", *arguments, chdir: File.expand_path("../../..", __dir__))
  end

  it "boots with eager loading on, running the boot checks without touching the database" do
    output, status = boot
    expect(status).to be_success, output
    expect(output).to include("Booted with 12 actions")
  end

  it "says rails actions:check needs the database when it cannot connect" do
    output, status = boot("check")
    expect(status).not_to be_success
    expect(output).to include("rails actions:check reads each action's model columns and asks its policy, so it needs the app's database")
  end

  it "says to prepare a database that has no tables yet, instead of blaming the policy" do
    output, status = Dir.mktmpdir { |folder| boot("check", database: "#{folder}/empty.sqlite3") }
    expect(status).not_to be_success
    expect(output).to include("Events::CreateAction: Event's table events does not exist: run bin/rails db:prepare first")
    expect(output).not_to include("schema_user")
  end
end
