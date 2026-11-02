RSpec.describe Events::RenameCommand do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  it "renames the event with the fields it accepts" do
    run({id: event.id, title: "Annual meeting"}, as: as_screen(manager))
    expect(event.reload.title).to eq("Annual meeting")
  end

  it "refuses an accepted field the person may not change, by name" do
    expect { run({id: event.id, title: "AGM", notes: "x"}, as: as_screen(manager)) }.to have_field_errors(:notes)
  end

  it "finds its record with its own lookup, inside the person's scope" do
    event.update!(status: "cancelled")
    expect { run({id: event.id, title: "Back"}, as: as_screen(manager)) }.to be_not_found
  end
end
