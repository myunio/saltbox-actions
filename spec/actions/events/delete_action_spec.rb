RSpec.describe Events::DeleteAction do
  let(:permitted_user) { manager }
  let(:unpermitted_user) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s} }

  it_behaves_like "refuses callers the action does not allow"

  context "with enforce_confirm off" do
    around { |example| with_settings(enforce_confirm: false) { example.run } }

    it_behaves_like "refuses callers the action does not allow"
  end

  it "removes the event once the person approves, answering with no body, and announces it" do
    expect { run_action(arguments, as: as_mcp(manager)) }.to be_refused.with(:confirmation_required)
    ActsAsTenant.with_tenant(Org.find(manager.org_id)) { Saltbox::Actions::Approval.waiting_for(manager).sole.approve! }
    expect { expect(run_action(arguments, as: as_mcp(manager)).body).to be_nil }.to announce_changes(event => :destroy)
    expect(Event.exists?(event.id)).to be(false)
  end

  it "is never run by the chat or a browser assistant" do
    expect(described_class).not_to be_runnable_for(as_assistant(manager))
    expect(described_class).not_to be_runnable_for(as_webmcp(manager))
  end
end
