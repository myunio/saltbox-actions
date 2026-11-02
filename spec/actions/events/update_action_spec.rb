RSpec.describe Events::UpdateAction do
  let(:permitted_account) { manager }
  let(:unpermitted_account) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s, title: "Annual general meeting"} }

  it "is an action spec, by its folder" do |example|
    expect(example.metadata[:type]).to eq(:action)
  end

  it_behaves_like "refuses callers the action does not allow"

  it_behaves_like "hides records the caller cannot see" do
    let(:hidden_arguments) { {id: Event.create!(org_id: 2, title: "Elsewhere").id.to_s} }
  end

  it "renames the event, with both names on the audit entry and the change announced" do
    expect { run(arguments, as: as_mcp(manager)) }
      .to change_audit_trail.on(event).by(manager).with(agent: "RSpec agent", surface: "mcp")
      .and announce_changes(event => :update)
    expect(event.reload.title).to eq("Annual general meeting")
  end

  it "refuses a field the person's role may not change, and a bad value, by name" do
    expect { run({id: event.id.to_s, notes: "secret"}, as: as_screen(manager)) }.to have_field_errors(:notes)
    expect(capacity: "lots").to be_invalid_against_schema
    expect(id: event.id.to_s, capacity: 40).not_to be_invalid_against_schema
  end

  it "is listed for and runnable by an agent, but not on a read-only token" do
    expect(described_class).to be_runnable_by(as_mcp(manager))
    expect(described_class).not_to be_listed_for(as_read_only(manager))
  end
end
