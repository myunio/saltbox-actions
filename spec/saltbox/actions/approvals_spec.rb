# The :approvals adapter: an agent's :confirm call waits as a request until
# the person approves it, then the same call runs once.
RSpec.describe Saltbox::Actions::Adapters::Confirmation::Approvals do
  include ActiveSupport::Testing::TimeHelpers

  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:connection) { Struct.new(:id).new(7) }
  let(:agent) { Saltbox::Actions::Caller.new(user: manager, surface: "mcp", agent_name: "Claude", connection:) }
  let(:cancel) do
    ->(caller = agent, reason: "Snow") { Saltbox::Actions::Invocation.call(action: "cancel_event", caller:, arguments: {id: event.id.to_s, reason:}) }
  end

  around do |example|
    original = Saltbox::Actions.config.confirm
    Saltbox::Actions.config.confirm { |invocation, action| ActionApproval.redeem!(invocation, action) }
    example.run
  ensure
    Saltbox::Actions.config.confirm(&original)
    ActionApproval.delete_all
  end

  it "refuses an agent's first call and leaves the person a request for that exact call" do
    expect { cancel.call }.to be_refused.with(:confirmation_required)
    request = ActionApproval.sole
    expect(request).to have_attributes(user_id: manager.id, connection_id: 7, surface: "mcp", agent_name: "Claude",
      action_name: "cancel_event", confirms: "cancel_event", arguments: {"id" => event.id.to_s, "reason" => "Snow"},
      approved_at: nil, title: Events::CancelAction.title)
    expect(ActionApproval.pending).to eq([request])
    expect(event.reload.status).to eq("draft")
  end

  it "tells the agent to call again once the person approves" do
    expect { cancel.call }.to raise_error(Saltbox::Actions::Error::ConfirmationRequired) { |error|
      expect(error.message).to eq("The person must approve this in Dummy before it runs. Then call it again with the same arguments.")
      expect(error.details).to eq("action" => "cancel_event")
    }
  end

  it "keeps one request while the agent calls again before the person answers" do
    2.times { expect { cancel.call }.to be_refused.with(:confirmation_required) }
    expect(ActionApproval.count).to eq(1)
  end

  it "runs the same call once after the person approves, then asks again" do
    expect { cancel.call }.to be_refused
    ActionApproval.sole.approve!
    cancel.call
    expect(event.reload.status).to eq("cancelled")
    expect(ActionApproval.approved).to be_empty
    expect { cancel.call }.to be_refused.with(:confirmation_required)
  end

  it "matches the arguments whatever their order" do
    expect(ActionApproval.digest({"a" => 1, "b" => {"d" => 2, "c" => [3]}})).to eq(ActionApproval.digest({"b" => {"c" => [3], "d" => 2}, "a" => 1}))
  end

  {
    "other arguments" => -> { cancel.call(reason: "Flood") },
    "another connection" => -> { cancel.call(agent.with(connection: Struct.new(:id).new(8))) },
    "another surface" => -> { cancel.call(agent.with(surface: "api")) },
    "another person" => -> { cancel.call(agent.with(user: other_org_manager)) }
  }.each do |difference, call|
    it "never lets an approval cover a call with #{difference}" do
      expect { cancel.call }.to be_refused
      ActionApproval.sole.approve!
      expect { instance_exec(&call) }.to be_refused.with(:confirmation_required)
      expect(event.reload.status).to eq("draft")
    end
  end

  it "lets an approval lapse after approval_lifetime, and a request after request_lifetime" do
    expect { cancel.call }.to be_refused
    request = ActionApproval.sole
    travel(ActionApproval.request_lifetime + 1.minute) { expect(ActionApproval.pending).to be_empty }
    request.approve!
    travel(ActionApproval.approval_lifetime + 1.minute) do
      expect { cancel.call }.to be_refused.with(:confirmation_required)
      expect(event.reload.status).to eq("draft")
    end
  end

  it "keeps the request of a call refused inside a change, whose writes roll back" do
    reschedule = Class.new(ApplicationAction) do
      def self.name = "Events::RescheduleAction"
      kind :change
      agents :allowed
      policy_rule :update?
      attribute :id

      def perform
        event.update!(title: "Moved")
        current_caller.confirm!(Events::CancelAction)
        event.update!(status: "cancelled")
        render :show
      end
    end
    run = -> { Saltbox::Actions::Invocation.call(action: reschedule, caller: agent, arguments: {id: event.id.to_s}) }

    expect { run.call }.to be_refused.with(:confirmation_required)
    expect(event.reload.title).to eq("AGM")
    expect(ActionApproval.sole).to have_attributes(action_name: "reschedule_event", confirms: "cancel_event")
    ActionApproval.sole.approve!
    run.call
    expect(event.reload).to have_attributes(title: "Moved", status: "cancelled")
  end

  it "never asks a person on a screen" do
    cancel.call(as_screen(manager))
    expect(ActionApproval.count).to eq(0)
  end
end
