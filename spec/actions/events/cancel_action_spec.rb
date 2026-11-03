RSpec.describe Events::CancelAction do
  let(:permitted_user) { manager }
  let(:unpermitted_user) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s, reason: "Snow"} }

  it_behaves_like "refuses callers the action does not allow"

  context "with enforce_confirm off" do
    around { |example| with_settings(enforce_confirm: false) { example.run } }

    it_behaves_like "refuses callers the action does not allow"
  end

  it "cancels the event once the person approves, and keeps the reason" do
    allow(Saltbox::Actions.config).to receive(:confirm).and_return(->(*) { true })
    run_action(arguments, as: as_mcp(manager))
    expect(event.reload).to have_attributes(status: "cancelled", notes: "Snow")
  end
end
