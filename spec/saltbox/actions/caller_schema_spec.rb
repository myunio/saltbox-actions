# Every surface builds a write action's schema for its caller, inside the
# caller's set-up. Here the schema user fails if used, and Event.new
# fails outside around_invocation, as a tenant gem's require_tenant does.
RSpec.describe "Schemas for the caller, on every surface", type: :request do
  let(:note_keeper) { User.new(id: 9, permissions: %w[events.view events.manage events.notes]) }
  let!(:event) { Event.create!(org_id: 1, title: "AGM") }

  def with_tenant
    @tenant = true
    yield
  ensure
    @tenant = false
  end

  before do
    config = Saltbox::Actions.config
    allow(config).to receive(:schema_user).and_return(->(_run) { raise "the schema user was used at run time" })
    allow(config).to receive(:around_invocation).and_return(->(caller, run) { with_tenant { run.call(caller) } })
    allow(Event).to receive(:new).and_wrap_original do |original, *arguments, **options, &block|
      raise "no tenant set" unless @tenant
      original.call(*arguments, **options, &block)
    end
    Saltbox::Actions::Registry.reset!
  end

  after { Saltbox::Actions::Registry.reset! }

  it "uses neither the schema user nor a record outside the caller's set-up" do
    expect { Events::CreateAction.input_schema }.to raise_error("the schema user was used at run time")
    expect { Event.new }.to raise_error("no tenant set")
  end

  it "lists each caller's own fields in tools, find_action, the actions list and the catalog" do
    expect(Saltbox::Actions::FrontDoor.tools(as_mcp(note_keeper)).map(&:name)).to include("find_action")
    found = ->(user) { Saltbox::Actions::FrontDoor.find("add an event", as_mcp(user))[:actions].find { it[:name] == "create_event" } }
    expect(found.call(note_keeper)[:input_schema]["properties"]).to have_key("notes")
    expect(found.call(manager)[:input_schema]["properties"]).not_to have_key("notes")
    expect(Saltbox::Actions::FrontDoor.list(as_mcp(manager), page: 1, page_size: 50)[:actions]).not_to be_empty
    entry = Saltbox::Actions::Registry.catalog(as_screen(note_keeper)).find { it["name"] == "create_event" }
    expect(entry.dig("input_schema", "properties")).to have_key("notes")
    expect(Saltbox::Actions::Registry.version).to match(/\A\h{16}\z/)
  end

  it "serves MCP tools/list and the API's actions list" do
    env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream", :input => {jsonrpc: "2.0", id: 1, method: "tools/list", params: {}}.to_json)
    status, _, body = Saltbox::Actions::MCP.call(env, caller: as_mcp(manager), name: "dummy", allowed_hosts: ["dummy.test"])
    expect(status).to eq(200)
    expect(JSON.parse(body.each.to_a.join).dig("result", "tools").pluck("name")).to include("find_action")
    get "/api/v1/actions", headers: {"Authorization" => "Bearer manager"}
    expect(response.parsed_body["data"].find { it["name"] == "create_event" }.dig("input_schema", "properties")).not_to have_key("notes")
  end

  it "runs a create and an update with each caller's fields" do
    run = ->(name, user, arguments) { Saltbox::Actions::Invocation.call(action: name, caller: as_screen(user), arguments:) }
    expect(run.call("create_event", note_keeper, {title: "Board", notes: "Quorum is 12"}).status).to eq(201)
    expect(run.call("update_event", manager, {id: event.id.to_s, title: "Annual meeting"}).status).to eq(200)
    expect(event.reload.title).to eq("Annual meeting")
    expect { run.call("update_event", manager, {id: event.id.to_s, notes: "x"}) }.to be_refused.with(:forbidden)
  end
end
