RSpec.describe WhoamiAction do
  let(:permitted_account) { stranger }
  let(:unpermitted_account) { stranger }
  let(:arguments) { {} }

  it "says who the connection acts for and where it comes from" do
    expect(run({}, as: as_mcp(stranger)).body["data"]).to eq("account_id" => 3, "surface" => "mcp", "agent" => "RSpec agent")
  end
end
