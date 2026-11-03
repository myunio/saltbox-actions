RSpec.describe Events::CancelAction do
  let(:permitted_user) { manager }
  let(:unpermitted_user) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s, reason: "Snow"} }

  it_behaves_like "refuses callers the action does not allow"

  context "with enforce_confirm on" do
    around { |example| with_settings(enforce_confirm: true) { example.run } }

    it_behaves_like "refuses callers the action does not allow"
  end

  it "cancels the event and keeps the reason" do
    run_action(arguments, as: as_mcp(manager))
    expect(event.reload).to have_attributes(status: "cancelled", notes: "Snow")
  end
end
