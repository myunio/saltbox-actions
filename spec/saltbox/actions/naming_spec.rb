RSpec.describe Saltbox::Actions::Naming do
  it "works out each action's name, CLI command, kind, id and policy rule from its class name" do
    expect(Event::UpdateAction).to have_attributes(action_name: "update_event", cli_command: %w[events update],
      kind: :change, takes_id?: true, policy_query: :update?, model: Event, area: "events", idempotent?: true)
    expect(Event::ListAction).to have_attributes(action_name: "list_events", kind: :read, takes_id?: false, policy_query: :index?)
    expect(Event::DeleteAction).to have_attributes(action_name: "delete_event", kind: :destructive, policy_query: :destroy?)
    expect(Event::ShowNotesAction).to have_attributes(action_name: "show_event_notes", policy_query: :view_notes?)
    expect(WhoamiAction).to have_attributes(action_name: "whoami", model: nil, kind: :read, cli_command: ["whoami"])
  end

  it "takes titles and descriptions from the locale file, building a title when it has none" do
    expect(Event::ListAction.title).to eq("List events")
    expect(Event::ShowNotesAction.title).to eq("Read an event's private notes")
    expect(Event::ListAction.description).to eq("Lists the events the person can see, newest first.")
    expect(Event::ListAction.field_description("status")).to eq("Only events with this status.")
    expect(Event::UpdateAction.field_description("id")).to eq("The record's id.")
  end
end
