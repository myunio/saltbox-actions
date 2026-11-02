RSpec.describe Events::ArchiveCommand do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  it "cancels the event, for a person who may delete it" do
    run({id: event.id}, as: as_screen(manager))
    expect(event.reload.status).to eq("cancelled")
    expect { run({id: event.id}, as: as_screen(reader)) }.to be_refused.with(:forbidden)
  end
end
