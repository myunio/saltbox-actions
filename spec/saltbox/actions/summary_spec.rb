# A list action sends agents each record's summary in place of its view.
# The dummy app's base class declares Event's summary; Event::CreateAction
# declares its own.
RSpec.describe Saltbox::Actions::Summary do
  before do
    Event.create!(org_id: 1, title: "AGM", starts_on: "2026-07-01", status: "published", notes: "Bring the minutes")
  end

  def list(base: ApplicationAction, &block)
    Class.new(base) do
      define_singleton_method(:name) { "Event::ListAction" }
      connections :allowed
      class_eval(&block) if block
      define_method(:perform) do
        authorize Event
        @events = policy_scope(Event).order(:id)
        render :index, meta: {page: 1}
      end
    end
  end

  def list_events(caller, action: Event::ListAction) = Saltbox::Actions::Invocation.call(name: action, caller:).as_json

  it "sends an agent each record's summary, computed fields included, with the meta beside it" do
    expect(list_events(as_mcp(manager))).to eq(
      "data" => {"events" => [{"id" => Event.last.id, "title" => "AGM", "starts_on" => "2026-07-01", "status" => "Published"}]},
      "meta" => {"page" => 1}
    )
    expect(list_events(as_api(manager))).to eq(list_events(as_mcp(manager)))
  end

  it "sends the same JSON in the envelope format" do
    body = list_events(as_mcp(manager))
    with_settings(result_format: :envelope) { expect(list_events(as_mcp(manager))).to eq(body) }
  end

  it "renders the view for a person on a screen, as before" do
    expect(list_events(as_screen(manager))).to eq("data" => {"events" => [{"id" => Event.last.id, "title" => "AGM"}]})
  end

  it "takes an action's own summary over its model's" do
    expect(list_events(as_mcp(manager), action: list { summary :id, :notes }).dig("data", "events"))
      .to eq([{"id" => Event.last.id, "notes" => "Bring the minutes"}])
  end

  it "renders the view for an agent when no summary is declared, or the action keeps no @events" do
    bare_base = Class.new(Saltbox::Actions::Base) { include Saltbox::Actions::Authorization::Pundit }
    expect(list(base: bare_base).summary).to be_nil
    expect(list_events(as_mcp(manager), action: list(base: bare_base))).to eq("data" => {"events" => [{"id" => Event.last.id, "title" => "AGM"}]})

    elsewhere = list
    elsewhere.define_method(:perform) do
      authorize Event
      @event = policy_scope(Event).first
      render :show
    end
    expect(list_events(as_mcp(manager), action: elsewhere).dig("data", "event")).to include("title" => "AGM", "capacity" => nil)
  end

  it "sends summaries only from a list action" do
    show = Saltbox::Actions::Invocation.call(name: Event::ShowAction, caller: as_mcp(manager), arguments: {id: Event.last.id.to_s})
    expect(show.body.dig("data", "event")).to include("capacity" => nil)
  end

  it "gives the catalogue the summary's fields, which the CLI prints as columns" do
    expect(Event::ListAction.definition["summary"]).to eq(%w[id title starts_on status])
    expect(Event::CreateAction.definition["summary"]).to eq(%w[id title starts_on])
    expect(Event::ListAction.definition["cli"]).not_to have_key("columns")
  end

  it "tells agents what a list returns, and which action gives the rest" do
    found = Saltbox::Actions::FrontDoor.call("find_action", {"query" => "list events"}, caller: as_mcp(manager))
    expect(found[:actions].find { it[:name] == "list_events" })
      .to include(returns: "Returns each event's id, title, starts_on, and status. Call show_event with its id for the rest.")
    expect(found[:actions].find { it[:name] == "show_event" }).not_to have_key(:returns)
  end

  it "stops the boot for a field the model lacks, or a list summary without id" do
    expect(Saltbox::Actions::Registry.problems(list { summary :title, :nickname }))
      .to eq(["Event has no nickname for its summary: name an attribute or method, or compute it",
        "its summary leaves out id, which agents need to call show: add :id"])
  end

  it "refuses a model summary with no fields, or a computed field that is not a lambda" do
    expect { ApplicationAction.summary(Event) }.to raise_error(ArgumentError, "summary Event names no field")
    expect { list { summary status: "Published" } }.to raise_error(ArgumentError, /summary status is a lambda/)
  end
end
