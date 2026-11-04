# The :approvals adapter: an agent's :confirm call waits as a request until
# the person approves it, then the same call runs once.
RSpec.describe Saltbox::Actions::Approval do
  include ActiveSupport::Testing::TimeHelpers

  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:connection) { Struct.new(:id).new(7) }
  let(:agent) { Saltbox::Actions::Caller.new(user: manager, surface: "mcp", agent_name: "Claude", connection:) }
  let(:cancel) do
    ->(caller = agent, reason: "Snow") { Saltbox::Actions::Invocation.call(action: "cancel_event", caller:, arguments: {id: event.id.to_s, reason:}) }
  end

  let(:approvals) { Saltbox::Actions::Approval }
  let(:ours) { Org.find_or_create_by!(id: manager.org_id) }

  after { approvals.delete_all }

  it "refuses an agent's first call and leaves the person a request for that exact call" do
    expect { cancel.call }.to be_refused.with(:confirmation_required)
    request = approvals.sole
    expect(request).to have_attributes(tenant_id: manager.org_id, user_id: manager.id, connection_id: 7, surface: "mcp", agent_name: "Claude",
      action_name: "cancel_event", confirms: "cancel_event", arguments: {"id" => event.id.to_s, "reason" => "Snow"},
      approved_at: nil, title: Events::CancelAction.title)
    expect(ActsAsTenant.with_tenant(ours) { approvals.waiting_for(manager).to_a }).to eq([request])
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
    expect(approvals.count).to eq(1)
  end

  it "runs the same call once after the person approves, then asks again" do
    expect { cancel.call }.to be_refused
    approvals.sole.approve!
    cancel.call
    expect(event.reload.status).to eq("cancelled")
    expect(approvals.approved).to be_empty
    expect { cancel.call }.to be_refused.with(:confirmation_required)
  end

  it "approves only a request still waiting" do
    expect { cancel.call }.to be_refused
    request = approvals.sole
    travel(approvals.request_lifetime + 1.minute) do
      expect { request.approve! }.to raise_error(ActiveRecord::RecordNotFound)
    end
    expect(request.reload.approved_at).to be_nil
    request.approve!
    expect(request.reload.approved_at).to be_present
    expect { request.approve! }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "matches the arguments whatever their order" do
    expect(approvals.digest({"a" => 1, "b" => {"d" => 2, "c" => [3]}})).to eq(approvals.digest({"b" => {"c" => [3], "d" => 2}, "a" => 1}))
  end

  {
    "other arguments" => -> { cancel.call(reason: "Flood") },
    "another connection" => -> { cancel.call(agent.with(connection: Struct.new(:id).new(8))) },
    "another surface" => -> { cancel.call(agent.with(surface: "api")) },
    "another person" => -> { cancel.call(agent.with(user: other_org_manager)) }
  }.each do |difference, call|
    it "never lets an approval cover a call with #{difference}" do
      expect { cancel.call }.to be_refused
      approvals.sole.approve!
      expect { instance_exec(&call) }.to be_refused.with(:confirmation_required)
      expect(event.reload.status).to eq("draft")
    end
  end

  it "lets an approval lapse after approval_lifetime, and a request after request_lifetime" do
    expect { cancel.call }.to be_refused
    request = approvals.sole
    travel(approvals.request_lifetime + 1.minute) { expect(approvals.pending).to be_empty }
    request.approve!
    travel(approvals.approval_lifetime + 1.minute) do
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
    expect(approvals.sole).to have_attributes(action_name: "reschedule_event", confirms: "cancel_event")
    approvals.sole.approve!
    run.call
    expect(event.reload).to have_attributes(title: "Moved", status: "cancelled")
  end

  it "asks the person about every agent's :confirm call once :approvals is declared" do
    expect { cancel.call }.to be_refused.with(:confirmation_required)
    expect(approvals.count).to eq(1)
  end

  it "keeps each approval in its tenant: another org neither sees it nor redeems it" do
    theirs = Org.create!(id: ours.id + 1)
    expect { cancel.call }.to be_refused
    approvals.sole.approve!
    expect(ActsAsTenant.with_tenant(theirs) { approvals.waiting_for(manager).to_a + approvals.approved.in_tenant.to_a }).to be_empty
    elsewhere = Saltbox::Actions::Invocation.new(Events::CancelAction, agent)
    ActsAsTenant.with_tenant(theirs) do
      expect { approvals.redeem!(elsewhere.tap { it.instance_variable_set(:@arguments, {"id" => event.id.to_s, "reason" => "Snow"}) }, Events::CancelAction) }
        .to raise_error(Saltbox::Actions::Error::ConfirmationRequired)
    end
    expect(approvals.approved.where(tenant_id: ours.id).count).to eq(1)
  end

  it "keeps each approval in acts_as_tenant's current tenant" do
    approvals.install!(user: "User", tenant: "Org")
    theirs = Org.create!(id: ours.id + 1)
    ActsAsTenant.with_tenant(ours) { approvals.create!(user_id: 1, surface: "mcp", action_name: "a", confirms: "a", arguments: {}, arguments_digest: "d", expires_at: 1.hour.from_now) }
    expect(approvals.sole.tenant_id).to eq(ours.id)
    expect(ActsAsTenant.with_tenant(theirs) { approvals.in_tenant.count }).to eq(0)
    expect(ActsAsTenant.with_tenant(ours) { approvals.in_tenant.count }).to eq(1)
  ensure
    approvals.install!(Saltbox::Actions.config.approvals)
  end

  it "refuses to keep or find an approval with no tenant set" do
    expect { approvals.in_tenant }.to raise_error(ArgumentError, /no tenant is set/)
    expect { approvals.create!(user_id: 1, surface: "mcp", action_name: "a", confirms: "a", arguments: {}, arguments_digest: "d", expires_at: 1.hour.from_now) }
      .to raise_error(ArgumentError, /no tenant is set/)
  end

  it "tells the agent the app's words, naming the person, the app and where to approve" do
    I18n.backend.store_translations(:en, actions: {errors: {approval_needed: "%{user} must approve this in %{app}, at %{url}."}})
    approvals.install!(Saltbox::Actions.config.approvals.merge(name: :id, url: "https://dummy.test/approvals"))
    expect { cancel.call }.to raise_error(Saltbox::Actions::Error::ConfirmationRequired, "1 must approve this in Dummy, at https://dummy.test/approvals.")
  ensure
    I18n.reload!
    approvals.install!(Saltbox::Actions.config.approvals)
  end

  it "takes only the settings it knows, and needs the person's class" do
    config = Saltbox::Actions::Configuration.new
    expect { config.approvals = {user: "Account", tenants: "Org"} }.to raise_error(ArgumentError, /not tenants/)
    expect { config.approvals = {tenant: "Org"} }.to raise_error(ArgumentError, /user:/)
    expect(config.approvals).to eq(user: "User")
  end

  it "never asks a person on a screen" do
    cancel.call(as_screen(manager))
    expect(approvals.count).to eq(0)
  end
end
