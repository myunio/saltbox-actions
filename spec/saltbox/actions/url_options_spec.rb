require "open3"

# A fresh development or test process draws its routes on first use. Its
# first render must still link with the routes' default_url_options
# (spec/render_in_new_process.rb), in a database of its own.
RSpec.describe "Links in a fresh process" do
  it "use the routes' host from the first render" do
    output, status = Dir.mktmpdir do |folder|
      Open3.capture2e({"DATABASE_URL" => "sqlite3:#{folder}/fresh.sqlite3"},
        RbConfig.ruby, "spec/render_in_new_process.rb", chdir: File.expand_path("../../..", __dir__))
    end
    expect(status).to be_success, output
    expect(output.lines.map(&:chomp)).to eq(["https://dummy.test/api/v1/actions"] * 2)
  end
end
