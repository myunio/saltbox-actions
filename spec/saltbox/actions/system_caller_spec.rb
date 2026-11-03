RSpec.describe "Caller.system" do
  include ActiveJob::TestHelper

  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:system) { Saltbox::Actions::Caller.system }

  it "is the app itself: not an agent, holding every scope, acting as SystemUser" do
    expect(system).to have_attributes(surface: "system", user: Saltbox::Actions::SystemUser.instance, agent_name: nil,
      scopes: Saltbox::Actions.config.scopes.values)
    expect(system).to be_system
    expect(system).not_to be_agent
    expect(as_screen(manager)).not_to be_system
    expect(Saltbox::Actions::Caller.system(agent_name: "Nightly cleanup").agent_name).to eq("Nightly cleanup")
  end

  it "is a surface of its own, whatever surfaces the app configures" do
    with_settings(surfaces: %w[screen api]) do
      expect(Saltbox::Actions::Caller.system.surface).to eq("system")
    end
  end

  it "runs what the policy allows the app, including an action closed to agents" do
    result = Events::UpdateAction.perform_now(caller: system, id: event.id, title: "Renamed")
    expect(result.body.dig("data", "event", "title")).to eq("Renamed")
    expect(Events::ShowNotesAction.agents).to eq(:never)
    expect(Events::ShowNotesAction.perform_now(caller: system, id: event.id).status).to eq(200)
    expect { Events::ShowNotesAction.perform_now(caller: as_mcp(manager), id: event.id) }.to be_refused.with(:human_required)
  end

  it "is refused what the policy does not allow the app, never let through" do
    expect { Events::DeleteAction.perform_now(caller: system, id: event.id) }.to be_refused.with(:forbidden)
    expect(Event.exists?(event.id)).to be(true)
    expect { run_action({}, as: system, action: Reports::CountEventsAction) }.to be_refused.with(:forbidden)
  end

  it "sees every tenant's records when the policy's scope says so" do
    elsewhere = Event.create!(org_id: 2, title: "Elsewhere")
    expect(Events::ShowAction.perform_now(caller: system, id: elsewhere.id).body.dig("data", "event", "title")).to eq("Elsewhere")
  end

  it "is never asked to confirm, with enforce_confirm on" do
    with_settings(enforce_confirm: true) do
      Events::CancelAction.perform_now(caller: system, id: event.id, reason: "Rain")
    end
    expect(event.reload.status).to eq("cancelled")
  end

  it "runs later as the same caller, through a job" do
    Events::UpdateAction.perform_later(caller: Saltbox::Actions::Caller.system(agent_name: "Nightly"), id: event.id, title: "Later")
    perform_enqueued_jobs
    expect(event.reload.title).to eq("Later")
    expect(event.versions.last).to have_attributes(whodunnit: nil, agent: "Nightly", surface: "system")
  end

  it "takes a user of the app's own, which the policy then sees" do
    expect(Saltbox::Actions::Caller.system(manager).user).to equal(manager)
    expect { Events::DeleteAction.perform_now(caller: Saltbox::Actions::Caller.system(manager), id: event.id) }.not_to raise_error
    expect(as_system).to be_system
    expect(as_system(manager).user).to equal(manager)
  end

  describe "at an entry point that serves requests" do
    it "is refused by MCP before any tool is listed or run" do
      env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        :input => {jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: "run_change_action",
                                                                         arguments: {name: "update_event", arguments: {id: event.id.to_s, title: "X"}}}}.to_json)
      expect { Saltbox::Actions::Adapters::EntryPoints::MCP.call(env, caller: system, name: "dummy", allowed_hosts: ["dummy.test"]) }
        .to raise_error(ArgumentError, /MCP and the assistant refuses Caller.system/)
      expect { Saltbox::Actions::Adapters::EntryPoints::MCP.invoke("run_change_action", {"name" => "update_event", "arguments" => {"id" => event.id.to_s, "title" => "X"}}, system) }
        .to raise_error(ArgumentError)
      expect(event.reload.title).to eq("AGM")
    end

    it "is refused by the assistant's tools" do
      expect { Saltbox::Actions::Adapters::EntryPoints::RubyLLMTool.for(system) }.to raise_error(ArgumentError, /Caller.system/)
    end
  end
end

# A controller whose current_caller wrongly returns the system caller.
class SystemCallerActionsController < ActionController::API
  include Saltbox::Actions::Adapters::EntryPoints::Controller

  private

  def current_caller = Saltbox::Actions::Caller.system
end

RSpec.describe "Caller.system over the JSON API" do
  it "is refused before the action runs" do
    event = Event.create!(org_id: 1, title: "AGM")
    env = Rack::MockRequest.env_for("/api/v1/actions/update_event", :method => "POST", "CONTENT_TYPE" => "application/json",
      :input => {arguments: {id: event.id.to_s, title: "X"}}.to_json)
    env["action_dispatch.request.path_parameters"] = {name: "update_event"}
    expect { SystemCallerActionsController.action(:run).call(env) }
      .to raise_error(ArgumentError, /SystemCallerActionsController refuses Caller.system/)
    expect(event.reload.title).to eq("AGM")
  end
end
