require "saltbox/actions/mcp"

RSpec.describe Saltbox::Actions::MCP do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  def rpc(method, params = {}, caller: as_mcp(manager))
    env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream", :input => {jsonrpc: "2.0", id: 1, method:, params:}.to_json)
    status, headers, body = described_class.call(env, caller:, name: "dummy", allowed_hosts: ["dummy.test"])
    [status, headers, JSON.parse(body.each.to_a.join)]
  end

  it "lists the caller's tools over streamable HTTP, never cached" do
    status, headers, body = rpc("tools/list")
    expect(status).to eq(200)
    expect(headers["cache-control"]).to eq("no-store")
    tools = body.dig("result", "tools")
    expect(tools.pluck("name")).to eq(%w[show_event whoami find_action run_read_action run_change_action run_destructive_action])
    expect(tools.first.dig("annotations", "readOnlyHint")).to be(true)
  end

  it "says what the app is in its instructions" do
    _, _, body = rpc("initialize", {protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: "spec", version: "1"}})
    expect(body.dig("result", "instructions")).to eq(Saltbox::Actions.config.instructions)
    expect(body.dig("result", "serverInfo", "name")).to eq("dummy")
  end

  it "answers a tool call with its body, and a refusal as a tool error the model can read" do
    _, _, body = rpc("tools/call", {name: "show_event", arguments: {id: event.id.to_s}})
    expect(body.dig("result", "structuredContent", "data", "event", "title")).to eq("AGM")
    _, _, body = rpc("tools/call", {name: "run_read_action", arguments: {name: "show_event_notes", arguments: {id: event.id.to_s}}})
    expect(body.dig("result", "isError")).to be(true)
    expect(body.dig("result", "structuredContent", "error", "code")).to eq("human_required")
  end

  it "lists every action when find_action is called with no arguments" do
    _, _, body = rpc("tools/call", {name: "find_action"})
    expect(body.dig("result", "isError")).to be(false)
    expect(body.dig("result", "structuredContent", "actions").pluck("name")).to include("delete_event", "whoami")
  end

  it "answers a delete's empty body as Done." do
    _, _, body = rpc("tools/call", {name: "run_destructive_action", arguments: {name: "delete_event", arguments: {id: event.id.to_s}}})
    expect(body.dig("result", "content", 0, "text")).to eq("Done.")
  end
end
