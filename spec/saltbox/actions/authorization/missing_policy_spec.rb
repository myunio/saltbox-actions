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
    _, _, body = Saltbox::Actions::Adapters::EntryPoints::MCP.call(env, caller: as_mcp(manager), name: "dummy", allowed_hosts: ["dummy.test"])
    JSON.parse(body.each.to_a.join)
  end

  RSpec::Matchers.define_negated_matcher :exclude, :include

  shared_examples "left out of every list" do
    it "is left out of the actions list, MCP and the assistant's tools, which still list the others" do
      expect(registry.catalog(as_api(manager)).pluck("name")).to include("list_events", "show_event").and exclude("export_reports_events")
      expect(mcp("tools/list").dig("result", "tools").pluck("name")).to include("show_event", "find_action", "run_read_action")
      found = mcp("tools/call", {name: "find_action"}).dig("result", "structuredContent", "actions").pluck("name")
      expect(found).to include("list_events").and exclude("export_reports_events")
      tools = Saltbox::Actions::Adapters::EntryPoints::RubyLLMTool.for(as_assistant(manager))
      listed = JSON.parse(tools.find { it.name == "find_action" }.execute.delete_prefix("<record-data>\n").delete_suffix("\n</record-data>"))
      expect(listed["actions"].pluck("name")).to include("list_events").and exclude("export_reports_events")
    end

    it "still fails when run" do
      expect { Saltbox::Actions::Invocation.call(action: missing, caller: as_api(manager), arguments: {}) }.to raise_error(missing_policy)
      expect { missing.perform_now(caller: as_api(manager)) }.to raise_error(missing_policy)
    end

    let(:warning) { /\Asaltbox-actions: Reports::ExportAction is left out of every actions list: Event has no \w+ policy in reports: add Reports::EventPolicy[^\n]*\n\z/ }

    it "warns once per action through the Rails logger, naming the policy to add, and stays left out after" do
      logged = StringIO.new
      allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(logged))
      expect { 2.times { registry.catalog(as_api(manager)) } }.not_to output.to_stderr
      expect(logged.string).to match(warning)
      expect([missing.policy_missing?, missing.policy_missing?]).to eq([true, true])
    end

    it "warns on stderr when Rails has no logger" do
      allow(Rails).to receive(:logger).and_return(nil)
      expect { 2.times { registry.catalog(as_api(manager)) } }.to output(warning).to_stderr
    end
  end

  context "with Pundit", authorization: :pundit do
    let(:missing) { stub_const("Reports::ExportAction", Class.new(ApplicationAction) { model Event }) }
    let(:missing_policy) { Pundit::NotDefinedError }

    it_behaves_like "left out of every list"
  end

  context "with ActionPolicy", authorization: :action_policy do
    # The dummy app's own actions are Pundit's; these are the others listed.
    let(:dummy_actions) do
      %w[Events::ListAction Events::ShowAction].map do |name|
        Class.new(Saltbox::Actions::Base) do
          include DummyBase

          define_singleton_method(:name) { name }
          policy_namespace ActionPolicies
          model Event
          featured
        end
      end
    end

    let(:missing) do
      stub_const("Reports::ExportAction", Class.new(Saltbox::Actions::Base) {
        include DummyBase

        define_verb :export, kind: :read, plural: true
        model Event
      })
    end
    let(:missing_policy) { ActionPolicy::NotFound }

    it_behaves_like "left out of every list"
  end
end
