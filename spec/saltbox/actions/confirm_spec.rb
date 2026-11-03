require "saltbox/actions/mcp"

# Configuration#enforce_confirm, the confirm hook and Caller#confirm!.
RSpec.describe "Confirming a :confirm action" do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:config) { Saltbox::Actions.config }
  let(:cancel) { ->(caller) { Saltbox::Actions::Invocation.call(action: "cancel_event", caller:, arguments: {id: event.id.to_s}) } }

  def approve(answer = true, &block)
    allow(config).to receive(:confirm).and_return(block || ->(*) { answer })
  end

  {screen: :allowed, webmcp: :allowed, api: :allowed, mcp: :allowed, assistant: :human_required}.each do |surface, answer|
    it "lets #{surface} run it with enforce_confirm off, and never asks" do
      approve { raise "asked" }
      outcome = expect { cancel.call(public_send(:"as_#{surface}", manager)) }
      (answer == :allowed) ? outcome.not_to(be_refused) : outcome.to(be_refused.with(answer))
    end
  end

  {screen: :allowed, webmcp: :confirmation_required, api: :confirmation_required,
   mcp: :confirmation_required, assistant: :human_required}.each do |surface, answer|
    it "answers #{surface} with #{answer} with enforce_confirm on and nothing approved" do
      with_settings(enforce_confirm: true) do
        outcome = expect { cancel.call(public_send(:"as_#{surface}", manager)) }
        (answer == :allowed) ? outcome.not_to(be_refused) : outcome.to(be_refused.with(answer))
      end
      expect(event.reload.status).not_to eq("cancelled") unless answer == :allowed
    end
  end

  it "runs it once the hook approves, and hands the hook the call" do
    seen = nil
    approve { |invocation, action| seen = [invocation.caller.surface, invocation.arguments, action] and true }
    with_settings(enforce_confirm: true) { cancel.call(as_mcp(manager)) }
    expect(event.reload.status).to eq("cancelled")
    expect(seen).to eq(["mcp", {"id" => event.id.to_s}, Events::CancelAction])
  end

  it "refuses when the hook answers anything but true, and passes on an error it raises" do
    with_settings(enforce_confirm: true) do
      approve("yes")
      expect { cancel.call(as_mcp(manager)) }.to be_refused.with(:confirmation_required)
      asked = Saltbox::Actions::Error::ConfirmationRequired.new("Approve it in Dummy's inbox", details: {"ask" => "1"})
      approve { raise asked }
      expect { cancel.call(as_api(manager)) }.to raise_error(asked)
    end
    expect(event.reload.status).not_to eq("cancelled")
  end

  it "asks again on each call of a reused Invocation, so one approval never covers another call" do
    other = Event.create!(org_id: 1, title: "Picnic")
    asked = []
    approve { |invocation, _action| asked << invocation.arguments["id"] and invocation.arguments["id"] == event.id.to_s }
    invocation = Saltbox::Actions::Invocation.new(Events::CancelAction, as_mcp(manager))
    with_settings(enforce_confirm: true) do
      invocation.call({id: event.id.to_s})
      expect { invocation.call({id: other.id.to_s}) }.to be_refused.with(:confirmation_required)
    end
    expect(other.reload.status).to eq("draft")
    expect(asked).to eq([event.id.to_s, other.id.to_s])
  end

  it "asks again on a retry after an approved call fails" do
    answers = [true, false]
    approve { answers.shift }
    invocation = Saltbox::Actions::Invocation.new(Events::CancelAction, as_mcp(manager))
    with_settings(enforce_confirm: true) do
      expect { invocation.call({id: "0"}) }.to be_not_found
      expect { invocation.call({id: event.id.to_s}) }.to be_refused.with(:confirmation_required)
    end
    expect(answers).to be_empty
    expect(event.reload.status).to eq("draft")
  end

  it "asks only once the person is allowed and the input is valid" do
    approve { raise "asked" }
    with_settings(enforce_confirm: true) do
      expect { cancel.call(as_mcp(reader)) }.to be_refused.with(:forbidden)
      expect { Saltbox::Actions::Invocation.call(action: "cancel_event", caller: as_mcp(manager), arguments: {id: event.id.to_s, reason: 1}) }
        .to have_field_errors(:reason)
    end
  end

  it "never asks for an :allowed action" do
    approve { raise "asked" }
    with_settings(enforce_confirm: true) do
      expect { Saltbox::Actions::Invocation.call(action: "update_event", caller: as_mcp(manager), arguments: {id: event.id.to_s, title: "New"}) }
        .not_to be_refused
    end
  end

  describe "Caller#confirm!, inline" do
    # A change that can also cancel, which a :confirm action guards.
    let(:action) do
      Class.new(ApplicationAction) do
        def self.name = "Events::RescheduleAction"
        kind :change
        agents :allowed
        policy_rule :update?
        attribute :id
        attribute :cancel, :boolean

        def perform
          event.update!(title: "Moved")
          current_caller.confirm!(Events::CancelAction) if cancel
          event.update!(status: cancel ? "cancelled" : "published")
          render :show
        end
      end
    end
    let(:reschedule) { ->(caller, cancel: true) { Saltbox::Actions::Invocation.call(action: action, caller:, arguments: {id: event.id.to_s, cancel:}) } }

    it "lets the call through with enforce_confirm off, and a person on a screen always" do
      reschedule.call(as_mcp(manager))
      expect(event.reload.status).to eq("cancelled")
      with_settings(enforce_confirm: true) { reschedule.call(as_screen(manager)) }
    end

    it "refuses with enforce_confirm on, rolling back the change, until the hook approves the named action" do
      with_settings(enforce_confirm: true) do
        expect { reschedule.call(as_mcp(manager)) }.to be_refused.with(:confirmation_required)
        expect(event.reload).to have_attributes(title: "AGM", status: "draft")
        reschedule.call(as_mcp(manager), cancel: false)
        expect(event.reload.status).to eq("published")
        approve { |_invocation, named| named == Events::CancelAction }
        reschedule.call(as_mcp(manager))
      end
      expect(event.reload.status).to eq("cancelled")
    end

    it "refuses a caller the named action's agents bar" do
      expect { reschedule.call(as_assistant(manager)) }.to be_refused.with(:human_required)
    end

    it "is for a running action only" do
      expect { as_mcp(manager).confirm!(Events::CancelAction) }.to raise_error(ArgumentError, /inside a running action/)
    end
  end

  describe "the refusal's shape" do
    it "keeps its code in the :type error format" do
      with_settings(error_format: :type) do
        expect(Saltbox::Actions::Error::ConfirmationRequired.new.as_json.dig("error", "type")).to eq("confirmation_required")
      end
    end

    it "is a tool error the model can read over MCP" do
      env = Rack::MockRequest.env_for("http://dummy.test/mcp", :method => "POST", "CONTENT_TYPE" => "application/json",
        "HTTP_ACCEPT" => "application/json, text/event-stream",
        :input => {jsonrpc: "2.0", id: 1, method: "tools/call",
                   params: {name: "run_change_action", arguments: {name: "cancel_event", arguments: {id: event.id.to_s}}}}.to_json)
      body = with_settings(enforce_confirm: true) do
        _, _, rack_body = Saltbox::Actions::MCP.call(env, caller: as_mcp(manager), name: "dummy", allowed_hosts: ["dummy.test"])
        JSON.parse(rack_body.each.to_a.join)
      end
      expect(body.dig("result", "isError")).to be(true)
      expect(body.dig("result", "structuredContent", "error")).to include("code" => "confirmation_required", "details" => {"action" => "cancel_event"})
      expect(event.reload.status).not_to eq("cancelled")
    end
  end
end
