RSpec.describe Saltbox::Actions::Invocation do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:invoke) { ->(name, arguments, caller) { described_class.call(action: name, caller:, arguments:) } }

  it "answers unknown_action for a name no action has" do
    expect { invoke.call("fly_event", {}, as_screen(manager)) }.to be_refused.with(:unknown_action)
  end

  it "refuses in a fixed order: feature, agents, access, scope, then the person's rights" do
    allow(Events::ShowNotesAction).to receive(:enabled_for?).and_return(false)
    expect { invoke.call("show_event_notes", {id: event.id.to_s}, as_mcp(stranger)) }.to be_refused.with(:not_found)
    allow(Events::ShowNotesAction).to receive(:enabled_for?).and_call_original
    expect { invoke.call("show_event_notes", {id: event.id.to_s}, as_mcp(stranger)) }.to be_refused.with(:human_required)
    expect { invoke.call("update_event", {id: event.id.to_s, title: 1}, as_read_only(stranger)) }.to be_refused.with(:insufficient_scope)
    expect { invoke.call("update_event", {id: event.id.to_s, title: 1}, as_screen(stranger)) }.to be_refused.with(:forbidden)
    expect { invoke.call("update_event", {id: event.id.to_s, title: 1}, as_screen(manager)) }.to have_field_errors(:title)
  end

  it "checks a generic run tool's kind after admission and before arguments" do
    expect { described_class.call(action: "update_event", caller: as_screen(manager), arguments: {nope: 1}, expected_kind: :read) }
      .to raise_error(Saltbox::Actions::Error::ValidationFailed, "update_event is a change action; run it with run_change_action")
  end

  it "runs a change in a transaction, notes each changed record and announces them before commit" do
    expect { invoke.call("update_event", {id: event.id.to_s, title: "Annual meeting"}, as_mcp(manager)) }
      .to announce_changes(event => :update)
      .and change_audit_trail.on(event).by(manager).with(agent: "RSpec agent", surface: "mcp")
    expect(Dummy::ANNOUNCED).to eq([{action: "update_event", changes: [["Event", event.id.to_s, "update"]]}])
  end

  it "runs a read with no change collection" do
    expect { invoke.call("show_event", {id: event.id.to_s}, as_screen(manager)) }.not_to announce_changes
  end

  it "undoes everything when the action fails partway" do
    allow(Saltbox::Actions.config).to receive(:on_changes).and_return(->(*) { raise "store failed" })
    expect { invoke.call("update_event", {id: event.id.to_s, title: "Gone"}, as_screen(manager)) }.to raise_error("store failed")
    expect(event.reload.title).to eq("AGM")
    expect(PaperTrail::Version.where(item_id: event.id.to_s, event: "update")).to be_empty
    expect(Saltbox::Actions::Current.invocation_id).to be_nil
  end

  it "answers a record the person cannot see as not found" do
    other = Event.create!(org_id: 2, title: "Elsewhere")
    expect { invoke.call("show_event", {id: other.id.to_s}, as_screen(manager)) }.to be_not_found
  end

  it "answers a model's validation failure with field errors" do
    expect { invoke.call("update_event", {id: event.id.to_s, status: "lost"}, as_screen(manager)) }.to have_field_errors(:status)
  end

  it "refuses a field the person may not change by name, and a reference to a record they cannot see" do
    expect { invoke.call("create_event", {title: "AGM", notes: "x"}, as_screen(manager)) }.to have_field_errors(:notes)
    hidden = Event.create!(org_id: 2, title: "Elsewhere")
    expect { invoke.call("create_event", {title: "AGM", parent: hidden.id.to_s}, as_screen(manager)) }.to have_field_errors(:parent)
    result = invoke.call("create_event", {title: "AGM", parent: event.id.to_s}, as_screen(manager))
    expect(Event.find(result.body.dig("data", "event", "id")).parent).to eq(event)
  end

  it "answers no content when an action renders nothing" do
    expect(invoke.call("delete_event", {id: event.id.to_s}, as_screen(manager))).to eq(Saltbox::Actions::Result.no_content)
  end

  it "maps an app's own error to the refusal callers see" do
    domain_error = Class.new(StandardError)
    Saltbox::Actions.config.map_error(domain_error) { Saltbox::Actions::Error.new("Locked", code: :locked, status: :conflict) }
    action = Class.new(ApplicationAction) do
      def self.name = "Events::LockAction"
      kind :change
      agents :allowed
      policy_rule :update?
      define_method(:perform) { raise domain_error }
    end
    expect { described_class.call(action: action, caller: as_screen(manager)) }.to be_refused.with(:locked)
  ensure
    Saltbox::Actions.config.error_mappings.pop
  end

  it "answers a delete that others depend on as in_use, a class of its own" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::PurgeAction"
      kind :destructive
      agents :confirm
      policy_rule :destroy?
      define_method(:perform) { raise ActiveRecord::DeleteRestrictionError, "attendees" }
    end
    expect { described_class.call(action:, caller: as_screen(manager)) }
      .to raise_error(Saltbox::Actions::Error::InUse) { expect([it.code, it.status]).to eq(["in_use", :unprocessable_content]) }
  end

  it "refuses to run an action from inside another" do
    Saltbox::Actions::Current.set(invocation_id: "outer") do
      expect { invoke.call("whoami", {}, as_screen(manager)) }.to raise_error(ArgumentError, /Nested action invocations/)
    end
  end

  it "fails an action that never calls authorize" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::PeekAction"
      kind :read
      agents :allowed
      policy_rule :show?
      def perform = render(json: {})
    end
    expect { described_class.call(action: action, caller: as_screen(manager)) }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end

  it "takes policy_scope as a list action's authorization, but still needs it" do
    listed = Class.new(ApplicationAction) do
      def self.name = "Events::ListAction"
      agents :allowed
      def perform
        @events = policy_scope(Event)
        render :index
      end
    end
    expect(described_class.call(action: listed, caller: as_screen(manager)).status).to eq(200)
    unscoped = Class.new(ApplicationAction) do
      def self.name = "Events::ListAction"
      agents :allowed
      def perform
        @events = Event.all
        render :index
      end
    end
    expect { described_class.call(action: unscoped, caller: as_screen(manager)) }.to raise_error(Pundit::PolicyScopingNotPerformedError)
  end

  it "refuses a read of an input the action does not declare" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::PeekAction"
      kind :read
      agents :allowed
      policy_rule :show?
      def perform = params[:colour]
    end
    expect { described_class.call(action: action, caller: as_screen(manager)) }
      .to raise_error(ArgumentError, "peek_event reads params[:colour] but declares no input colour")
  end

  describe "a connection's access (Caller#access)" do
    let(:events_read_only) { Struct.new(:kinds) { def allows?(action) = kinds.include?(action.kind) }.new([:read]) }
    let(:connection) { Saltbox::Actions::Caller.new(user: manager, surface: "mcp", agent_name: "Claude", access: events_read_only) }

    it "hides and refuses what the access does not reach, with the app's refusal" do
      refusal = Saltbox::Actions::Error::InsufficientScope.new("Not allowed changes in Events", details: {"area" => "events", "needs" => "change"})
      allow(Saltbox::Actions.config).to receive(:on_access_refused).and_return(->(_caller, _action) { refusal })
      expect(Events::UpdateAction).not_to be_listed_for(connection)
      expect(Events::ShowAction).to be_listed_for(connection)
      expect { invoke.call("update_event", {id: event.id.to_s}, connection) }.to raise_error(refusal)
      expect(refusal.as_json.dig("error", "details")).to eq("area" => "events", "needs" => "change")
    end

    it "runs the app's after_change_commit hook once a change commits" do
      seen = []
      allow(Saltbox::Actions.config).to receive(:after_change_commit).and_return(->(invocation, result) { seen << [invocation.action, result.status] })
      invoke.call("update_event", {id: event.id.to_s, title: "AGM 2026"}, as_mcp(manager))
      expect(seen).to eq([[Events::UpdateAction, 200]])
    end
  end

  it "checks the app's error mappings before its own, so an app may pass an ActiveRecord error through" do
    allow(Saltbox::Actions.config).to receive(:error_mappings).and_return([[ActiveRecord::RecordNotFound, ->(_) {}]])
    expect { invoke.call("show_event", {id: "0"}, as_screen(manager)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "checks the input with the action's own validate_arguments" do
    allow(Events::ShowAction).to receive(:validate_arguments).and_wrap_original do |original, arguments, caller|
      original.call(arguments.merge("id" => event.id.to_s), caller)
    end
    expect(invoke.call("show_event", {}, as_screen(manager)).body.dig("data", "event", "title")).to eq("AGM")
  end
end
