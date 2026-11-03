require "open3"

# A fresh app boots lazily, as a development server or console does, with its
# base class defined before the declaration (spec/boot_lazy_app.rb). The
# declared adapter still authorizes every action, run straight through
# perform_now, and again after a reload.
RSpec.describe "A declared authorization adapter in a lazily booted app" do
  def boot(*arguments)
    Open3.capture2e(RbConfig.ruby, "-Ilib", "spec/boot_lazy_app.rb", *arguments, chdir: File.expand_path("../../..", __dir__))
  end

  it "fails an action that never authorizes, with Pundit" do
    output, status = boot("pundit")
    expect(status).to be_success, output
    expect(output).to include("first: Pundit::AuthorizationNotPerformedError")
  end

  it "fails it with ActionPolicy, before and after a reload" do
    output, status = boot("action_policy", "reload")
    expect(status).to be_success, output
    expect(output.lines.map(&:strip)).to eq([
      "first: Saltbox::Actions::AuthorizationNotPerformedError, perform ran: true",
      "reloaded: true",
      "after reload: Saltbox::Actions::AuthorizationNotPerformedError, perform ran: true"
    ])
  end
end
