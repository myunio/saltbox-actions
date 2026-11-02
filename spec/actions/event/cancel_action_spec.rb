RSpec.describe Event::CancelAction do
  let(:permitted_account) { manager }
  let(:unpermitted_account) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s, reason: "Snow"} }

  it_behaves_like "refuses callers the action does not allow"

  it "cancels the event and keeps the reason" do
    run(arguments, as: as_mcp(manager))
    expect(event.reload).to have_attributes(status: "cancelled", notes: "Snow")
  end
end
