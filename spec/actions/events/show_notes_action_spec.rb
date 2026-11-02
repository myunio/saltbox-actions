RSpec.describe Events::ShowNotesAction do
  let(:permitted_account) { Account.new(id: 9, permissions: %w[events.view events.notes]) }
  let(:unpermitted_account) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM", notes: "Quorum is 12") }
  let(:arguments) { {id: event.id.to_s} }

  it_behaves_like "refuses callers the action does not allow"

  it "shows the notes to the person on a screen" do
    expect(run(arguments, as: as_screen(permitted_account)).body.dig("data", "event", "notes")).to eq("Quorum is 12")
  end
end
