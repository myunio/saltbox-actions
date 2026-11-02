# A list action sends agents each record's summary in place of its view.
# The dummy app's base class declares Event's summary; Event::CreateAction
# declares its own.
RSpec.describe Saltbox::Actions::Summary do
  before do
    Event.create!(org_id: 1, title: "AGM", starts_on: "2026-07-01", status: "published", notes: "Bring the minutes")
  end

  def list(base: ApplicationAction, name: "Event::ListAction", perform: nil, &block)
    perform ||= proc do
      authorize Event
      @events = policy_scope(Event).order(:id)
      render :index, meta: {page: 1}
    end
    Class.new(base) do
      define_singleton_method(:name) { name }
      connections :allowed
      class_eval(&block) if block
      define_method(:perform, &perform)
    end
  end

  def list_events(caller, action: Event::ListAction) = Saltbox::Actions::Invocation.call(name: action, caller:).as_json

  it "sends an agent each record's summary, computed fields included, with the meta beside it" do
    expect(list_events(as_mcp(manager))).to eq(
      "data" => {"events" => [{"id" => Event.last.id, "title" => "AGM", "starts_on" => "2026-07-01", "status" => "Published"}]},
      "meta" => {"page" => 1}
    )
    expect([as_api(manager), as_webmcp(manager), as_assistant(manager)].map { list_events(it) }.uniq).to eq([list_events(as_mcp(manager))])
  end

  it "sends an empty list as an empty array" do
    Event.delete_all
    expect(list_events(as_mcp(manager))).to eq("data" => {"events" => []}, "meta" => {"page" => 1})
  end

  it "matches the output schema the catalogue gives agents, in either result format" do
    expect(Saltbox::Actions::Invocation.call(name: Event::ListAction, caller: as_mcp(manager))).to match_output_schema(Event::ListAction.summary_output_schema)
    expect(Event::ListAction.definition["output_schema"]).to eq(Event::ListAction.summary_output_schema)
    with_settings(result_format: :envelope) do
      expect(Saltbox::Actions::Invocation.call(name: Event::ListAction, caller: as_mcp(manager))).to match_output_schema(Event::ListAction.summary_output_schema)
    end
    expect(Event::ListAction.summary_output_schema.dig("properties", "data", "properties", "events", "items", "properties"))
      .to eq("id" => {"type" => "integer"}, "title" => {"type" => "string"}, "starts_on" => {"type" => %w[string null], "format" => "date"},
        "status" => {"type" => %w[string number boolean null]})
  end

  it "keeps a full agent page small and free of links, while a screen still gets the view" do
    24.times { Event.create!(org_id: 1, title: "Event #{it}", starts_on: "2026-08-01", notes: "https://files.example.com/signed?token=#{it}") }
    json = JSON.generate(list_events(as_mcp(manager)))
    expect(JSON.parse(json).dig("data", "events").size).to eq(25)
    expect(json.bytesize).to be < 12.kilobytes
    expect(json).not_to include("://")
    expect(list_events(as_screen(manager), action: list { summary :id, :notes }).dig("data", "events").size).to eq(25)
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

  it "renders the view for an agent when no summary is declared" do
    bare_base = Class.new(Saltbox::Actions::Base) { include Saltbox::Actions::Authorization::Pundit }
    expect(list(base: bare_base).summary).to be_nil
    expect(list_events(as_mcp(manager), action: list(base: bare_base))).to eq("data" => {"events" => [{"id" => Event.last.id, "title" => "AGM"}]})
  end

  it "refuses to render a list with a summary that hands over no records, for every caller" do
    no_records = list(perform: proc do
      authorize Event
      @event = policy_scope(Event).first
      render :show
    end)
    nil_records = list(perform: proc do
      authorize Event
      @events = nil
      policy_scope(Event)
      render :index
    end)
    [no_records, nil_records].product([as_mcp(manager), as_screen(manager)]).each do |action, caller|
      expect { list_events(caller, action:) }.to raise_error(ArgumentError, "Event::ListAction sends agents Event's summary: set @events to its records, or render collection:")
    end
  end

  it "refuses render json: from a list with a summary, so the summary is never skipped" do
    as_json = list(perform: proc do
      authorize Event
      @events = policy_scope(Event)
      render json: {data: {events: @events.as_json}}
    end)
    expect { list_events(as_mcp(manager), action: as_json) }
      .to raise_error(ArgumentError, "Event::ListAction sends agents Event's summary: render a template with @events or collection:, not json:")
  end

  it "summarizes a renamed list action's records handed over with collection:" do
    upcoming = list(name: "Reports::ListUpcomingAction", perform: proc do
      authorize Event
      render :index, collection: policy_scope(Event).where(status: "published")
    end) do
      action_name "upcoming_events"
      kind :read
      model Event
      authorize :index?
    end
    expect(list_events(as_mcp(manager), action: upcoming).dig("data", "events").pluck("title")).to eq(["AGM"])
    show = list(name: "Event::ShowAction", perform: proc do
      @event = policy_scope(Event).first
      authorize @event
      render :show, collection: [@event]
    end)
    expect { Saltbox::Actions::Invocation.call(name: show, caller: as_mcp(manager), arguments: {id: Event.last.id.to_s}) }.to raise_error(ArgumentError, /render collection: is for a list action with a summary/)
  end

  it "refuses a field whose value is not plain, so no other attribute rides inside it" do
    smuggling = list { summary :id, record: ->(event) { event } }
    expect { list_events(as_mcp(manager), action: smuggling) }.to raise_error(ArgumentError, /summary record is a Event: a summary field holds text/)
    expect { list_events(as_mcp(manager), action: list { summary :id, details: ->(event) { event.as_json } }) }.to raise_error(ArgumentError, /summary details is a Hash/)
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
      .to include(response_description: "Returns each event's id, title, starts_on, and status. Call show_event with its id for the rest.")
    expect(found[:actions].find { it[:name] == "show_event" }).not_to have_key(:response_description)
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
