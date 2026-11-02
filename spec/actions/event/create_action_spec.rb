RSpec.describe Event::CreateAction do
  let(:permitted_account) { manager }
  let(:unpermitted_account) { reader }
  let(:arguments) { {title: "Picnic", starts_on: "2026-07-01"} }

  it_behaves_like "refuses callers the action does not allow"

  it "creates the event in the person's organization" do
    result = run(arguments, as: as_screen(manager))
    expect(result.status).to eq(201)
    expect(Event.find(result.body.dig("data", "event", "id"))).to have_attributes(title: "Picnic", org_id: 1)
  end

  it "needs a title" do
    expect { run({starts_on: "2026-07-01"}, as: as_screen(manager)) }.to have_field_errors(:title)
  end
end
