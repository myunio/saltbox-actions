# The engine's action on the host app's model, refused by the engine's policy.
RSpec.describe Billing::Events::ListAction do
  let(:permitted_user) { User.new(id: 5, permissions: %w[billing.view]) }
  let(:unpermitted_user) { manager }
  let(:arguments) { {} }

  it_behaves_like "refuses callers the action does not allow"

  it "lists the organization's events through Billing::EventPolicy" do
    mine = Event.create!(org_id: 1, title: "AGM")
    Event.create!(org_id: 2, title: "Elsewhere")
    expect(run_action({}, as: as_api(permitted_user)).body.dig("data", "events").pluck("id")).to eq([mine.id])
  end
end
