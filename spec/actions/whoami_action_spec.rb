RSpec.describe WhoamiAction do
  let(:permitted_user) { stranger }
  let(:arguments) { {} }

  # Everyone may ask who they are, so it defines no unpermitted_user.
  it_behaves_like "refuses callers the action does not allow"

  it "says who the connection acts for and where it comes from" do
    expect(run_action({}, as: as_mcp(stranger)).body["data"]).to eq("user_id" => 3, "surface" => "mcp", "agent" => "RSpec agent")
  end
end
