RSpec.describe Event::DeleteAction do
  let(:permitted_account) { manager }
  let(:unpermitted_account) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s} }

  it_behaves_like "refuses callers the action does not allow"

  context "with enforce_confirm on" do
    around { |example| with_settings(enforce_confirm: true) { example.run } }

    it_behaves_like "refuses callers the action does not allow"
  end

  it "removes the event, answering with no body, and announces it" do
    expect { expect(run(arguments, as: as_mcp(manager)).body).to be_nil }.to announce_changes(event => :destroy)
    expect(Event.exists?(event.id)).to be(false)
  end

  it "is never run by the chat or a browser assistant" do
    expect(described_class).not_to be_runnable_by(as_assistant(manager))
    expect(described_class).not_to be_runnable_by(as_webmcp(manager))
  end
end
