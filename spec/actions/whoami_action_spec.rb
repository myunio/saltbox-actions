RSpec.describe WhoamiAction do
  let(:permitted_account) { stranger }
  let(:arguments) { {} }

  # Everyone may ask who they are, so it defines no unpermitted_account.
  it_behaves_like "refuses callers the action does not allow"

  it "says who the connection acts for and where it comes from" do
    expect(run({}, as: as_mcp(stranger)).body["data"]).to eq("account_id" => 3, "surface" => "mcp", "agent" => "RSpec agent")
  end
end
