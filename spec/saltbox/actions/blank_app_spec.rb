require "open3"

# The README's setup is all a Pundit app needs: a settings-only initializer,
# an empty base class and one action, booted in a fresh app with eager
# loading on, as production does (spec/boot_blank_app.rb).
RSpec.describe "A blank app on the README's setup" do
  it "boots its 12 lines, with no block in them, and runs the action" do
    output, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "spec/boot_blank_app.rb", chdir: File.expand_path("../../..", __dir__))
    expect(status).to be_success, output
    expect(output.lines.map(&:strip)).to eq([
      "seam: 12 lines, 0 blocks besides configure",
      %(ran: 200 {"id":1,"title":"Dune"}),
      "saved: Dune"
    ])
  end
end
