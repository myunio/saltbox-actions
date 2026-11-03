RSpec.describe Events::PostponeAction do
  let(:permitted_user) { manager }
  let(:unpermitted_user) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM", starts_on: Date.new(2026, 11, 2)) }
  let(:arguments) { {id: event.id.to_s, starts_on: "2026-12-01", reason: "Snow"} }

  it_behaves_like "refuses callers the action does not allow"

  it_behaves_like "hides records the caller cannot see" do
    let(:hidden_arguments) { {id: Event.create!(org_id: 2, title: "Elsewhere").id.to_s, starts_on: "2026-12-01"} }
  end

  it "moves the event to the new day and keeps the reason" do
    run(arguments, as: as_mcp(manager))
    expect(event.reload).to have_attributes(starts_on: Date.new(2026, 12, 1), notes: "Snow")
  end

  it "takes its kind, its member record and its defaults from the verb the app defines" do
    expect(described_class).to have_attributes(kind: :change, takes_id?: true, idempotent?: true, agents: :allowed, policy_rule: :postpone?)
  end

  it "needs the new day, as its schema says, and refuses a reason its validation does not allow, by field" do
    expect(described_class.input_schema["required"]).to eq(%w[id starts_on])
    expect(id: event.id.to_s).to be_invalid_against_schema
    expect { run(arguments.merge(reason: "x" * 201), as: as_screen(manager)) }.to have_field_errors(:reason)
    expect(event.reload.starts_on).to eq(Date.new(2026, 11, 2))
  end
end
