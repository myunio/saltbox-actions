RSpec.describe Reports::CountEventsAction do
  before do
    Event.create!(org_id: 1, title: "AGM", status: "published")
    Event.create!(org_id: 1, title: "Picnic")
    Event.create!(org_id: 2, title: "Elsewhere", status: "published")
  end

  it "counts the events the person may see, by status" do
    result = run_action({status: "published"}, as: as_api(manager))
    expect(result.body).to eq("count" => 1)
    expect(result.meta).to eq(page: 1)
    expect(result).to match_output_schema
  end

  it "is listed and run only for someone holding every permission it declares" do
    expect(described_class).to be_listed_for(as_api(manager))
    expect(described_class).not_to be_listed_for(as_api(reader))
    expect { run_action({}, as: as_api(reader)) }.to be_refused.with(:forbidden)
  end
end
