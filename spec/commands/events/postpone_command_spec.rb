RSpec.describe Events::PostponeCommand do
  let(:permitted_account) { manager }
  let(:unpermitted_account) { reader }
  let(:event) { Event.create!(org_id: 1, title: "AGM", starts_on: Date.new(2026, 5, 1)) }
  let(:arguments) { {id: event.id, starts_on: "2026-06-01"} }

  it "is an action spec, by its folder" do |example|
    expect(example.metadata[:type]).to eq(:action)
  end

  it_behaves_like "refuses callers the action does not allow"

  it_behaves_like "hides records the caller cannot see" do
    let(:hidden_arguments) { {id: Event.create!(org_id: 2, title: "Elsewhere").id, starts_on: "2026-06-01"} }
  end

  it "moves the event, and its view gets the record the command found" do
    body = run(arguments.merge(reason: "Snow"), as: as_mcp(manager)).body
    expect(body.dig("data", "event", "starts_on")).to eq("2026-06-01")
    expect(event.reload).to have_attributes(starts_on: Date.new(2026, 6, 1), notes: "Snow")
  end

  it "refuses what its validations refuse, by field" do
    expect { run({id: event.id, starts_on: "2026-04-01"}, as: as_screen(manager)) }.to have_field_errors(:starts_on)
    expect { run({id: event.id}, as: as_screen(manager)) }.to have_field_errors(:starts_on)
  end
end
