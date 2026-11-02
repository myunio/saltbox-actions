RSpec.describe Events::ExportCommand do
  it "counts the events the person can see, by status" do
    Event.create!(org_id: 1, title: "AGM")
    Event.create!(org_id: 2, title: "Elsewhere")
    expect(run({}, as: as_screen(reader)).body).to eq("count" => 1)
    expect(run({status: "published"}, as: as_screen(reader)).body).to eq("count" => 0)
    expect { run({status: "lost"}, as: as_screen(reader)) }.to have_field_errors(:status)
  end
end
