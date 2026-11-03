RSpec.describe Events::ListAction do
  let(:permitted_user) { reader }
  let(:unpermitted_user) { stranger }
  let(:arguments) { {} }

  it_behaves_like "refuses callers the action does not allow"

  it "lists only the organization's events, filtered by status" do
    mine = Event.create!(org_id: 1, title: "AGM", status: "published")
    Event.create!(org_id: 1, title: "Draft")
    Event.create!(org_id: 2, title: "Elsewhere", status: "published")
    expect(run_action({status: "published"}, as: as_api(reader)).body.dig("data", "events").pluck("id")).to eq([mine.id])
  end
end
