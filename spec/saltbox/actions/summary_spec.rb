# A list action sends agents each record's summary in place of its view.
# The dummy app's base class declares Event's summary; Events::CreateAction
# declares its own.
RSpec.describe Saltbox::Actions::Summary do
  before do
    Event.create!(org_id: 1, title: "AGM", starts_on: "2026-07-01", status: "published", notes: "Bring the minutes")
  end

  def list(base: ApplicationAction, name: "Events::ListAction", perform: nil, &block)
    perform ||= proc do
      authorize Event
      @events = policy_scope(Event).order(:id)
      render :index, meta: {page: 1}
    end
    Class.new(base) do
      define_singleton_method(:name) { name }
      agents :allowed
      class_eval(&block) if block
      define_method(:perform, &perform)
    end
  end

  def list_events(caller, action: Events::ListAction) = Saltbox::Actions::Invocation.call(action: action, caller:).as_json

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

  it "matches the output schema the catalog gives agents, in either result format" do
    expect(Saltbox::Actions::Invocation.call(action: Events::ListAction, caller: as_mcp(manager))).to match_output_schema(Events::ListAction.summary_output_schema)
    expect(Events::ListAction.definition["output_schema"]).to eq(Events::ListAction.summary_output_schema)
    with_settings(result_format: :envelope) do
      expect(Saltbox::Actions::Invocation.call(action: Events::ListAction, caller: as_mcp(manager))).to match_output_schema(Events::ListAction.summary_output_schema)
    end
    expect(Events::ListAction.summary_output_schema.dig("properties", "data", "properties", "events", "items", "properties"))
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
    bare_base = Class.new(Saltbox::Actions::Base) { include Saltbox::Actions::Adapters::Authorization::Pundit }
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
      expect { list_events(caller, action:) }.to raise_error(ArgumentError, "Events::ListAction sends agents Event's summary: set @events to its records, or render collection:")
    end
  end

  it "refuses render json: alone from a list with a summary, so the summary is never skipped" do
    as_json = list(perform: proc do
      authorize Event
      @events = policy_scope(Event)
      render json: {data: {events: @events.as_json}}
    end)
    expect { list_events(as_mcp(manager), action: as_json) }
      .to raise_error(ArgumentError, "Events::ListAction sends agents Event's summary: render a template with @events, " \
        "or hand over its records with collection:, beside json: if you send one")
  end

  it "sends screens the json: of a serializer, and agents the summaries of the collection: beside it" do
    serialized = list(perform: proc do
      records = policy_scope(Event).order(:id)
      render json: {events: records.map { {title: it.title, notes: it.notes} }}, collection: records
    end)
    expect(list_events(as_screen(manager), action: serialized)).to eq("events" => [{"title" => "AGM", "notes" => "Bring the minutes"}])
    expect(list_events(as_mcp(manager), action: serialized).dig("data", "events", 0).keys).to eq(%w[id title starts_on status])
  end

  it "summarizes a renamed list action's records handed over with collection:" do
    upcoming = list(name: "Events::ListUpcomingAction", perform: proc do
      authorize Event
      render :index, collection: policy_scope(Event).where(status: "published")
    end) do
      action_name "upcoming_events"
      kind :read
      model Event
      policy_rule :index?
    end
    expect(list_events(as_mcp(manager), action: upcoming).dig("data", "events").pluck("title")).to eq(["AGM"])
    show = list(name: "Events::ShowAction", perform: proc do
      @event = policy_scope(Event).first
      authorize @event
      render :show, collection: [@event]
    end)
    expect { Saltbox::Actions::Invocation.call(action: show, caller: as_mcp(manager), arguments: {id: Event.last.id.to_s}) }.to raise_error(ArgumentError, /render collection: is for a list action with a summary/)
  end

  it "sends a decimal column as text, as its schema says" do
    Event.last.update!(price: "12.34")
    priced = list { summary :id, :price }
    result = Saltbox::Actions::Invocation.call(action: priced, caller: as_mcp(manager))
    expect(result.as_json.dig("data", "events", 0, "price")).to eq("12.34")
    expect(priced.summary_output_schema.dig("properties", "data", "properties", "events", "items", "properties", "price"))
      .to eq("type" => %w[number string null])
    expect(result).to match_output_schema(priced.summary_output_schema)
  end

  it "refuses a record or relation in a summarized list's meta, for every caller" do
    leaky = list(perform: proc do
      authorize Event
      @events = policy_scope(Event)
      render :index, meta: {page: 1, records: [@events.first], all: @events}
    end)
    [as_mcp(manager), as_screen(manager)].each do |caller|
      expect { list_events(caller, action: leaky) }
        .to raise_error(ArgumentError, /\AEvents::ListAction sends agents Event's summary: meta.records\[0\] holds a Event; meta is plain data/)
    end
  end

  it "takes only plain data in a summarized list's meta, so a Set or a Struct of records is refused" do
    meta_of = lambda do |meta|
      list(perform: proc do
        authorize Event
        @events = policy_scope(Event)
        render :index, meta: meta.call(@events)
      end)
    end
    expect { list_events(as_mcp(manager), action: meta_of.call(->(events) { {records: Set.new(events)} })) }
      .to raise_error(ArgumentError, /meta.records holds a Set; meta is plain data/)
    page = Struct.new(:number, :records)
    expect { list_events(as_mcp(manager), action: meta_of.call(->(events) { {page: page.new(1, events.to_a)} })) }
      .to raise_error(ArgumentError, /meta.page holds a .*; meta is plain data/)
    plain = {page: 1, per: 25.0, more: false, sort: :title, on: Date.new(2026, 7, 1), at: Time.utc(2026), next: nil, filters: [{status: "draft"}]}
    expect(list_events(as_mcp(manager), action: meta_of.call(->(_events) { plain }))["meta"]).to include("page" => 1, "sort" => "title", "filters" => [{"status" => "draft"}])
  end

  it "checks a field's JSON, so a value that serializes to an object is refused" do
    sneaky = Class.new(String) { def as_json(*) = {"org_id" => 1} }
    expect { list_events(as_mcp(manager), action: list { summary :id, title: ->(_event) { sneaky.new("AGM") } }) }
      .to raise_error(ArgumentError, /summary title is a .*: a summary field holds text/)
  end

  it "refuses a field whose value is not plain, so no other attribute rides inside it" do
    smuggling = list { summary :id, record: ->(event) { event } }
    expect { list_events(as_mcp(manager), action: smuggling) }.to raise_error(ArgumentError, /summary record is a Event: a summary field holds text/)
    expect { list_events(as_mcp(manager), action: list { summary :id, details: ->(event) { event.as_json } }) }.to raise_error(ArgumentError, /summary details is a Hash/)
  end

  it "sends summaries only from a list action" do
    show = Saltbox::Actions::Invocation.call(action: Events::ShowAction, caller: as_mcp(manager), arguments: {id: Event.last.id.to_s})
    expect(show.body.dig("data", "event")).to include("capacity" => nil)
  end

  it "gives the catalog the summary's fields, which the CLI prints as columns" do
    expect(Events::ListAction.definition["summary"]).to eq(%w[id title starts_on status])
    expect(Events::CreateAction.definition["summary"]).to eq(%w[id title starts_on])
    expect(Events::ListAction.definition["cli"]).not_to have_key("columns")
  end

  it "tells agents what a list returns, and which action gives the rest" do
    found = Saltbox::Actions::AgentTools.call("find_action", {"query" => "list events"}, caller: as_mcp(manager))
    expect(found[:actions].find { it[:name] == "list_events" })
      .to include(output_description: "Returns each event's id, title, starts_on, and status. Call show_event with its id for the rest.")
    expect(found[:actions].find { it[:name] == "show_event" }).not_to have_key(:output_description)
  end

  it "points a back-office list at its own show action, never the public one" do
    admin_list = list(name: "Admin::Events::ListAction")
    expect(admin_list.summary_note).to eq("Returns each event's id, title, starts_on, and status.")
    admin_show = Class.new(ApplicationAction) { define_singleton_method(:name) { "Admin::Events::ShowAction" } }
    allow(Saltbox::Actions::Registry).to receive(:find).and_call_original
    allow(Saltbox::Actions::Registry).to receive(:find).with("show_admin_event").and_return(admin_show)
    expect(admin_list.summary_note).to end_with("Call show_admin_event with its id for the rest.")
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
