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

  it "hands the changes.saltbox_actions subscribers the call's id, the caller and the action" do
    seen = []
    ActiveSupport::Notifications.subscribed(->(event) { seen << event.payload }, "changes.saltbox_actions") do
      invoke.call("update_event", {id: event.id.to_s, title: "Annual meeting"}, as_mcp(manager))
    end
    expect(seen.sole).to include(action: Events::UpdateAction, changes: [["Event", event.id.to_s, "update"]], invocation_id: a_string_matching(/\A\h{8}-/))
    expect(seen.sole[:caller].surface).to eq("mcp")
  end

  it "undoes everything when a subscriber fails, since it hears inside the transaction" do
    failing = ->(*) { raise "store failed" }
    run = -> { invoke.call("update_event", {id: event.id.to_s, title: "Gone"}, as_screen(manager)) }
    expect { ActiveSupport::Notifications.subscribed(failing, "changes.saltbox_actions", &run) }.to raise_error("store failed")
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

  context "with a belongs_to whose foreign key is not named after it" do
    before do
      stub_const("Venue", Class.new(ApplicationRecord) {
        self.table_name = "events"
        belongs_to :host, class_name: "Event", foreign_key: :parent_id, optional: true
      })
      stub_const("VenuePolicy", Class.new(EventPolicy) { def permitted_attributes = %i[title parent_id] })
    end

    let(:create) do
      Class.new(ApplicationAction) do
        def self.name = "Venues::CreateAction"

        def perform
          venue = authorize(policy_scope(Venue).new(org_id: 1, **permitted_attributes(Venue)))
          render json: {id: venue.tap(&:save!).id}
        end
      end
    end

    it "takes it under the association's name and refuses a record the person cannot see" do
      expect(create.input_schema["properties"].keys).to eq(%w[title host])
      hidden = Event.create!(org_id: 2, title: "Elsewhere")
      expect { described_class.call(action: create, caller: as_screen(manager), arguments: {title: "Hall", host: hidden.id}) }.to have_field_errors(:host)
      expect { described_class.call(action: create, caller: as_screen(manager), arguments: {title: "Hall", parent_id: hidden.id}) }.to have_field_errors(:parent_id)
      id = described_class.call(action: create, caller: as_screen(manager), arguments: {title: "Hall", host: event.id}).body["id"]
      expect(Venue.find(id).host).to eq(event)
    end

    it "refuses a foreign key it cannot look up: a polymorphic or composite one, or one two associations share" do
      Venue.belongs_to :subject, polymorphic: true, foreign_key: :parent_id, optional: true
      expect { create.input_schema }.to raise_error(ArgumentError, /parent_id is the foreign key of host and subject/)
      stub_const("Venue", Class.new(ApplicationRecord) {
        self.table_name = "events"
        belongs_to :subject, polymorphic: true, foreign_key: :parent_id, optional: true
      })
      expect { create.input_schema }.to raise_error(ArgumentError, /parent_id is the foreign key of subject, which is polymorphic/)
      stub_const("Venue", Class.new(ApplicationRecord) {
        self.table_name = "events"
        belongs_to :host, class_name: "Event", foreign_key: %i[org_id parent_id], primary_key: %i[org_id id], optional: true
      })
      expect { create.input_schema }.to raise_error(ArgumentError, /parent_id is part of host's composite foreign key/)
    end

    it "refuses a belongs_to that names another primary key, whose value the id sent is not" do
      stub_const("Venue", Class.new(ApplicationRecord) {
        self.table_name = "events"
        belongs_to :host, class_name: "Event", foreign_key: :parent_id, primary_key: :capacity, optional: true
      })
      visible = Event.create!(org_id: 1, title: "Hall", capacity: 99)
      hidden = Event.create!(org_id: 2, title: "Elsewhere", capacity: visible.id)
      expect { create.input_schema }.to raise_error(ArgumentError, /parent_id is the foreign key of host, which points at Event#capacity, not its primary key/)
      expect(Saltbox::Actions::Registry.problems(create)).to include(/points at Event#capacity, not its primary key/)
      expect { described_class.call(action: create, caller: as_screen(manager), arguments: {title: "Hall", host: visible.id}) }.to raise_error(ArgumentError)
      expect(Venue.where.not(parent_id: nil).map(&:host)).not_to include(hidden)
    end
  end

  it "answers no content when an action renders nothing" do
    expect(invoke.call("delete_event", {id: event.id.to_s}, as_screen(manager))).to eq(Saltbox::Actions::Result.no_content)
  end

  it "answers an app's own error with its rescue_from, inside the caller's set-up" do
    domain_error = stub_const("Events::Locked", Class.new(StandardError))
    action = Class.new(ApplicationAction) do
      def self.name = "Events::LockAction"
      kind :change
      agents :allowed
      policy_rule :update?
      rescue_from(domain_error) { raise Saltbox::Actions::Error.new("Locked in #{ActsAsTenant.current_tenant.id}", code: :locked, status: :conflict) }
      define_method(:perform) { raise domain_error }
    end
    expect { described_class.call(action: action, caller: as_screen(manager)) }.to raise_error(Saltbox::Actions::Error, "Locked in 1") { |error|
      expect(error.code).to eq("locked")
    }
  end

  it "answers with what a rescue_from handler renders when it does not raise, as a controller's does" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::GuessAction"
      kind :read
      agents :allowed
      policy_rule :show?
      rescue_from(KeyError) { render json: {guess: "none"} }
      def perform = raise(KeyError)
    end
    expect(described_class.call(action: action, caller: as_screen(manager)).body).to eq("guess" => "none")
  end

  it "takes an error by its cause, as a controller does, and passes the gem's own refusals to a handler too" do
    seen = []
    action = Class.new(ApplicationAction) do
      def self.name = "Events::WrapAction"
      kind :read
      agents :allowed
      policy_rule :show?
      attribute :title, :string
      rescue_from(StandardError) { |error| seen << error.class and raise error }
      define_method(:perform) do
        Event.find(0)
      rescue ActiveRecord::RecordNotFound
        raise "the view failed"
      end
    end
    expect { described_class.call(action: action, caller: as_screen(manager)) }.to raise_error(RuntimeError, "the view failed")
    expect { described_class.call(action: action, caller: as_screen(manager), arguments: {title: 1}) }.to have_field_errors(:title)
    expect(seen).to eq([RuntimeError, Saltbox::Actions::Error::ValidationFailed])
    by_cause = Class.new(ApplicationAction) do
      def self.name = "Events::WrapAction"
      kind :read
      agents :allowed
      policy_rule :show?
      def perform
        Event.find(0)
      rescue ActiveRecord::RecordNotFound
        raise "the view failed"
      end
    end
    expect { described_class.call(action: by_cause, caller: as_screen(manager)) }.to be_not_found
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

  it "needs authorize in a list action with no model, whose role was never asked" do
    Event.create!(org_id: 1, title: "AGM")
    unasked = Class.new(ApplicationAction) do
      def self.name = "ListEventsAction"
      agents :allowed
      permission :everyone
      def perform = render(json: {titles: policy_scope(Event).pluck(:title)})
    end
    expect { described_class.call(action: unasked, caller: as_screen(stranger)) }.to raise_error(Pundit::AuthorizationNotPerformedError)
    asked = Class.new(unasked) do
      def self.name = "ListEventsAction"

      def perform
        authorize Event, :index?
        super
      end
    end
    expect { described_class.call(action: asked, caller: as_screen(stranger)) }.to be_refused.with(:forbidden)
    expect(described_class.call(action: asked, caller: as_screen(manager)).status).to eq(200)
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

    it "hides and refuses what the access does not reach, as OutsideAccess, an insufficient_scope naming the area and level" do
      expect(Events::UpdateAction).not_to be_listed_for(connection)
      expect(Events::ShowAction).to be_listed_for(connection)
      expect { invoke.call("update_event", {id: event.id.to_s}, connection) }.to raise_error(Saltbox::Actions::Error::OutsideAccess) { |error|
        expect(error).to have_attributes(code: "insufficient_scope", status: :forbidden, action: Events::UpdateAction, area: "events", needs: "change")
        expect(error.as_json.dig("error", "details")).to eq("area" => "events", "needs" => "change")
      }
      expect(Saltbox::Actions::Error::OutsideAccess.new(action: Events::ShowAction)).to be_a(Saltbox::Actions::Error::InsufficientScope)
    end

    it "lets the app answer the refusal in its own words, with the caller's tenant still set" do
      refuse = proc { |error| raise Saltbox::Actions::Error::InsufficientScope.new("Not allowed #{error.needs} in #{error.area} (org #{ActsAsTenant.current_tenant.id})") }
      with_rescue_from(Saltbox::Actions::Error::OutsideAccess, refuse) do
        expect { invoke.call("update_event", {id: event.id.to_s}, connection) }
          .to raise_error(Saltbox::Actions::Error::InsufficientScope, "Not allowed change in events (org 1)")
      end
    end

    it "runs the action's after_commit callbacks once a change commits, with its caller and result" do
      seen = []
      action = Class.new(Events::UpdateAction) do
        def self.name = "Events::UpdateAction"
        after_commit { seen << [self.class.action_name, current_caller.surface, result.status] }
      end
      invoke.call(action, {id: event.id.to_s, title: "AGM 2026"}, as_mcp(manager))
      expect(seen).to eq([["update_event", "mcp", 200]])
    end
  end

  it "finds the app's rescue_from before its own, so an app may pass an ActiveRecord error through" do
    expect { invoke.call("show_event", {id: "0"}, as_screen(manager)) }.to be_not_found
    with_rescue_from(ActiveRecord::RecordNotFound, proc { |error| raise error }) do
      expect { invoke.call("show_event", {id: "0"}, as_screen(manager)) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  it "refuses a validate_arguments override that never calls super, which would leave each default unset" do
    allow(Events::ListAction).to receive(:validate_arguments) { |arguments, _caller| arguments.to_h.stringify_keys }
    expect { invoke.call("list_events", {}, as_screen(manager)) }
      .to raise_error(ArgumentError, /Events::ListAction\.validate_arguments never called super, so page and page_size would have no default/)
  end

  it "checks the input with the action's own validate_arguments" do
    allow(Events::ShowAction).to receive(:validate_arguments).and_wrap_original do |original, arguments, caller|
      original.call(arguments.merge("id" => event.id.to_s), caller)
    end
    expect(invoke.call("show_event", {}, as_screen(manager)).body.dig("data", "event", "title")).to eq("AGM")
  end
end
