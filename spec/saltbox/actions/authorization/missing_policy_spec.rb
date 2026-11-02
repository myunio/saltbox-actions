require "saltbox/actions/mcp"
require "saltbox/actions/ruby_llm"

# An action whose policy does not exist, such as Reports::ExportAction before
# Reports::EventPolicy is added, is left out of every list, so the other
# actions stay listed; running it still fails, and the app is warned once.
RSpec.describe "An action whose policy is missing" do
  let(:registry) { Saltbox::Actions::Registry }
  let(:dummy_actions) { registry.actions }

  before do
    actions = dummy_actions
    allow(registry).to receive(:actions).and_return([*actions, missing])
  end

  def mcp(method, params = {})
    env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream", :input => {jsonrpc: "2.0", id: 1, method:, params:}.to_json)
    _, _, body = Saltbox::Actions::MCP.call(env, caller: as_mcp(manager), name: "dummy", allowed_hosts: ["dummy.test"])
    JSON.parse(body.each.to_a.join)
  end

  RSpec::Matchers.define_negated_matcher :exclude, :include

  shared_examples "left out of every list" do
    it "is left out of the actions list, MCP and the assistant's tools, which still list the others" do
      expect(registry.catalogue(as_api(manager)).pluck("name")).to include("list_events", "show_event").and exclude("export_reports_events")
      expect(mcp("tools/list").dig("result", "tools").pluck("name")).to include("show_event", "find_action", "run_read_action")
      found = mcp("tools/call", {name: "find_action"}).dig("result", "structuredContent", "actions").pluck("name")
      expect(found).to include("list_events").and exclude("export_reports_events")
      tools = Saltbox::Actions::RubyLLMTool.for(as_assistant(manager))
      listed = JSON.parse(tools.find { it.name == "find_action" }.execute.delete_prefix("<record-data>\n").delete_suffix("\n</record-data>"))
      expect(listed["actions"].pluck("name")).to include("list_events").and exclude("export_reports_events")
    end

    it "still fails when run" do
      expect { Saltbox::Actions::Invocation.call(name: missing, caller: as_api(manager), arguments: {}) }.to raise_error(missing_policy)
      expect { missing.perform_now(caller: as_api(manager)) }.to raise_error(missing_policy)
    end

    it "warns once per action, naming the policy to add" do
      expect { 2.times { registry.catalogue(as_api(manager)) } }
        .to output(/\Asaltbox-actions: Reports::ExportAction is left out of every actions list: Event has no \w+ policy in reports: add Reports::EventPolicy[^\n]*\n\z/).to_stderr
    end
  end

  context "with Pundit" do
    let(:missing) { stub_const("Reports::ExportAction", Class.new(ApplicationAction) { model Event }) }
    let(:missing_policy) { Pundit::NotDefinedError }

    it_behaves_like "left out of every list"
  end

  context "with ActionPolicy" do
    let(:missing) do
      stub_const("Reports::ExportAction", Class.new(Saltbox::Actions::Base) {
        include Saltbox::Actions::Authorization::ActionPolicy

        model Event
      })
    end
    let(:missing_policy) { ActionPolicy::NotFound }

    it_behaves_like "left out of every list"
  end
end
