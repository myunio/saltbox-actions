require "saltbox/actions/mcp"

# The dummy app mounts an isolated engine, Billing, whose initializer adds
# its own action folder with the namespace "billing".
RSpec.describe "Actions from an engine" do
  let(:registry) { Saltbox::Actions::Registry }
  let(:engine_folder) { Billing::Engine.root.join("app/actions") }
  let(:billing_clerk) { Account.new(id: 5, permissions: %w[billing.view]) }

  def with_paths(paths)
    with_settings(action_paths: paths) do
      registry.reset!
      yield
    ensure
      registry.reset!
    end
  end

  it "loads the engine's actions beside the app's, without eager loading" do
    expect(Rails.application.config.eager_load).to be(false)
    expect(registry.actions).to include(Billing::Invoices::ListAction, Events::ListAction)
    expect(registry.catalogue(as_api(billing_clerk)).pluck("name")).to include("list_billing_invoices")
  end

  it "finds the engine's actions as subclasses too, as when eager loading" do
    with_settings(every_file_an_action: false) do
      registry.reset!
      expect(registry.actions).to include(Billing::Invoices::ListAction, Events::ListAction)
    ensure
      registry.reset!
    end
  end

  it "serves the engine's actions over MCP" do
    env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      :input => {jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: "run_read_action", arguments: {name: "list_billing_invoices", arguments: {}}}}.to_json)
    _, _, body = Saltbox::Actions::MCP.call(env, caller: as_mcp(billing_clerk), name: "dummy", allowed_hosts: ["dummy.test"])
    expect(JSON.parse(body.each.to_a.join).dig("result", "structuredContent")).to eq("invoices" => [])
  end

  it "names the engine's actions with its folder's namespace in place of the engine's module" do
    expect(Billing::Invoices::ListAction).to have_attributes(action_name: "list_billing_invoices",
      cli_command: %w[billing-invoices list], title: "List billing invoices")
    with_paths(["app/actions", Saltbox::Actions::ActionPaths::Path.new(path: engine_folder, namespace: "pay")]) do
      expect(Billing::Invoices::ListAction).to have_attributes(action_name: "list_pay_invoices", cli_command: %w[pay-invoices list])
    end
  end

  it "names an engine's action on a host model with the folder's namespace once, and asks the engine's policy" do
    expect(Billing::Events::ListAction).to have_attributes(action_name: "list_billing_events",
      cli_command: %w[billing-events list], title: "List billing events", policy_class: Billing::EventPolicy)
    expect(registry.catalogue(as_api(billing_clerk)).pluck("name")).to include("list_billing_events")
    with_paths(["app/actions", Saltbox::Actions::ActionPaths::Path.new(path: engine_folder, namespace: "pay")]) do
      expect(Billing::Events::ListAction).to have_attributes(action_name: "list_pay_events", cli_command: %w[pay-events list])
    end
  end

  it "names them from the class, as any namespaced model, when the folder has no namespace" do
    with_paths(["app/actions", engine_folder]) do
      expect(Billing::Invoices::ListAction).to have_attributes(action_name: "list_billing_invoices", cli_command: %w[invoices list])
    end
  end

  it "loads each action once when one folder is inside another, naming it by the inner folder" do
    with_paths(["app/actions", engine_folder, Saltbox::Actions::ActionPaths::Path.new(path: "app/actions/events", namespace: "special")]) do
      expect(registry.actions.count(Events::ListAction)).to eq(1)
      expect(Events::ListAction.action_name).to eq("list_special_events")
      expect(Reports::CountEventsAction.action_name).to eq("count_events")
    end
  end

  it "loads each action once when one folder is listed relative and absolute" do
    with_paths(["app/actions", Rails.root.join("app/actions"), "app/actions/", engine_folder]) do
      expect(registry.actions.size).to eq(registry.actions.uniq.size)
      expect(registry.actions).to include(Events::ListAction, Billing::Invoices::ListAction)
    end
  end

  it "loads each action once from overlapping folders when actions are found as subclasses" do
    with_settings(every_file_an_action: false) do
      with_paths(["app/actions", Rails.root.join("app/actions"), "app/actions/event", engine_folder]) do
        expect(registry.actions.count(Events::ListAction)).to eq(1)
      end
    end
  end

  it "refuses a namespace that cannot be part of a name" do
    expect { Saltbox::Actions::ActionPaths.new.add("x", namespace: "Billing") }.to raise_error(ArgumentError, /lowercase/)
  end

  it "warns about an action outside every folder, such as an engine's before it adds its folder" do
    [Billing::Events::ListAction, Billing::Invoices::ListAction].each(&:name)
    with_paths(["app/actions"]) do
      expect { registry.actions }.to output(/Billing::Events::ListAction, Billing::Invoices::ListAction inherit from ApplicationAction but are outside the action folders \(app\/actions\)/).to_stderr
      expect(registry.actions).not_to include(Billing::Invoices::ListAction)
    end
  end

  it "does not warn while every action is in a folder" do
    registry.reset!
    expect { registry.actions }.not_to output.to_stderr
  end
end
