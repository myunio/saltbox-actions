# An action in a module its model is not in, such as Admin::Events::ListAction
# on Event, asks that namespace's policy, as Pundit's authorize [:admin, event]
# does: Admin::EventPolicy, never EventPolicy.
RSpec.describe "Namespaced policies" do
  let(:admin) { Account.new(id: 6, permissions: %w[events.view events.manage events.admin]) }
  let(:invoke) { ->(klass, arguments, caller) { Saltbox::Actions::Invocation.call(name: klass, caller:, arguments:) } }
  let!(:ours) { Event.create!(org_id: 1, title: "AGM") }
  let!(:theirs) { Event.create!(org_id: 2, title: "Elsewhere") }

  def admin_event_policy(parent = EventPolicy)
    Class.new(parent) do
      def index? = user.can?("events.admin")
      def show? = index?
      def update? = index?
      def export? = index?
      def permitted_attributes = %i[title notes parent_id]
    end.tap { it.const_set(:Scope, Class.new(EventPolicy::Scope) { def resolve = @scope.all }) }
  end

  def admin_action(name, &body)
    stub_const(name, Class.new(ApplicationAction, &body))
  end

  # Pundit and ActionPolicy both let a model, or each of its records, name
  # its policy with policy_class. In a policy namespace that never reaches
  # the model's own policy.
  def name_model_policy(on, policy)
    (on == :model) ? Event.define_singleton_method(:policy_class) { policy } : Event.define_method(:policy_class) { policy }
  end

  after do
    Event.singleton_class.remove_method(:policy_class) if Event.singleton_class.method_defined?(:policy_class, false)
    Event.remove_method(:policy_class) if Event.method_defined?(:policy_class, false)
  end

  shared_examples "a model that names its own policy" do |on|
    before { name_model_policy(on, model_policy) }

    it "refuses a member list, show and update through the namespace's policy (named on the #{on})" do
      expect(list.policy_class).to eq(Admin::EventPolicy)
      expect { invoke.call(list, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect { invoke.call(show, {id: ours.id}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect { invoke.call(update, {id: ours.id, title: "Member write"}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(ours.reload.title).to eq("AGM")
    end

    it "takes an admin's records, fields and references through it too (named on the #{on})" do
      expect(invoke.call(list, {}, as_api(admin)).body.dig("data", "events").pluck("title")).to eq(%w[AGM Elsewhere])
      expect(invoke.call(show, {id: theirs.id}, as_api(admin)).body.dig("data", "event", "title")).to eq("Elsewhere")
      invoke.call(update, {id: theirs.id, notes: "Moved", parent: ours.id}, as_api(admin))
      expect(theirs.reload).to have_attributes(notes: "Moved", parent_id: ours.id)
      expect(update.input_schema(as_api(admin))["properties"].keys).to include("notes")
    end

    it "fails closed when the namespace has no policy, and rails actions:check names it (named on the #{on})" do
      hide_const("Admin::EventPolicy")
      expect(list.policy_class).to be_nil
      expect { invoke.call(list, {}, as_api(manager)) }.to raise_error(missing_policy)
      expect(Saltbox::Actions::Registry.problems(list).join).to include("add Admin::EventPolicy")
    end
  end

  # Every module an action is in that its model is not in is part of its
  # policy namespace, a single module too. A declared namespace holds for
  # the class that declared it and its subclasses in the same modules; a
  # subclass in other modules adds its own after it.
  shared_examples "the modules around an action" do
    def define(name, parent = base, &body) = stub_const(name, Class.new(parent, &body || proc {}))
    def count(klass, caller) = invoke.call(klass, {}, as_api(caller)).body["count"]

    let(:counting) do
      proc do
        def perform
          skip_authorization
          render json: {count: policy_scope(Event).count}
        end
      end
    end

    it "asks a single module's policy when the model is not in it" do
      stub_const("Admin::EventPolicy", admin_policy)
      export = define("Admin::ExportAction") { model Event }.tap { it.class_eval(&counting) }
      expect(export).to have_attributes(action_name: "export_admin_events", policy_namespace: [:admin], policy_class: Admin::EventPolicy)
      expect { invoke.call(export, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(count(export, admin)).to eq(2)
    end

    it "fails closed for a single module without its policy, until the action declares policy_namespace false" do
      report = define("Reports::ExportAction") { model Event }.tap { it.class_eval(&counting) }
      expect(report).to have_attributes(action_name: "export_reports_events", policy_namespace: [:reports], policy_class: nil)
      expect { invoke.call(report, {}, as_api(manager)) }.to raise_error(missing_policy)
      expect(Saltbox::Actions::Registry.problems(report).join).to include("add Reports::EventPolicy")
      report.policy_namespace false
      expect(report.policy_class).to eq(public_policy)
    end

    it "says an action looks nested when its outer module names a model, and still fails closed" do
      nested = define("Events::Invoices::ListAction") { model Billing::Invoice }
      expect(nested.policy_class).to be_nil
      expect(Saltbox::Actions::Registry.problems(nested).join).to include("add Events::Billing::InvoicePolicy")
        .and include("If Events groups actions under the Event model, declare policy_namespace false to ask Billing::InvoicePolicy")
    end

    it "re-derives an inherited policy_namespace false in a subclass in other modules" do
      stub_const("Admin::EventPolicy", admin_policy)
      parent = define("Events::ExportAllAction") { policy_namespace false }.tap { it.class_eval(&counting) }
      child = define("Admin::Events::ExportAllAction", parent)
      expect(parent.policy_class).to eq(public_policy)
      expect(child).to have_attributes(policy_namespace: [:admin], policy_class: Admin::EventPolicy)
      expect { invoke.call(child, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(count(child, admin)).to eq(2)
      expect(define("Events::ExportOtherAction", parent).policy_namespace).to eq([])
    end

    it "puts a base class's declared namespace before the action's own modules" do
      stub_const("Staff::Admin::EventPolicy", admin_policy)
      staff = define("StaffAction") { policy_namespace :staff }
      child = define("Admin::Events::ExportAllAction", staff).tap { it.class_eval(&counting) }
      expect(child).to have_attributes(policy_namespace: %i[staff admin], policy_class: Staff::Admin::EventPolicy)
      expect { invoke.call(child, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(count(child, admin)).to eq(2)
      expect(define("Events::ExportAllAction", staff).policy_namespace).to eq([:staff])
    end
  end

  describe "with Pundit" do
    let(:list) do
      admin_action("Admin::Events::ListAction") do
        def perform
          @events = policy_scope(Event).order(:id)
          render :index
        end
      end
    end

    let(:update) do
      admin_action("Admin::Events::UpdateAction") do
        def perform
          event.update!(permitted_attributes(event))
          render :show
        end
      end
    end

    context "when the namespace has its policy" do
      before { stub_const("Admin::EventPolicy", admin_event_policy) }

      it "asks it, before any record loads and in policy_scope" do
        expect(list.policy_class).to eq(Admin::EventPolicy)
        expect(list.permitted?(manager)).to be(false)
        expect { invoke.call(list, {}, as_api(manager)) }.to be_refused.with(:forbidden)
        titles = invoke.call(list, {}, as_api(admin)).body.dig("data", "events").pluck("title")
        expect(titles).to eq(%w[AGM Elsewhere])
      end

      it "loads, authorizes and takes fields for a member action through it" do
        expect { invoke.call(update, {id: ours.id, title: "X"}, as_api(manager)) }.to be_refused.with(:forbidden)
        invoke.call(update, {id: theirs.id, notes: "Moved", parent: ours.id}, as_api(admin))
        expect(theirs.reload).to have_attributes(notes: "Moved", parent_id: ours.id)
        expect(update.input_schema(as_api(admin))["properties"].keys).to eq(%w[id title notes parent])
      end

      it "passes rails actions:check" do
        expect(Saltbox::Actions::Registry.problems(list)).to eq([])
      end
    end

    let(:show) { admin_action("Admin::Events::ShowAction") { def perform = render(:show) } }

    context "when the model names its own policy" do
      before { stub_const("Admin::EventPolicy", admin_event_policy) }

      let(:model_policy) { EventPolicy }
      let(:missing_policy) { Pundit::NotDefinedError }

      it_behaves_like "a model that names its own policy", :model
      it_behaves_like "a model that names its own policy", :record
    end

    context "when the action's own code asks" do
      before { stub_const("Admin::EventPolicy", admin_event_policy) }

      it "answers policy(record) from the namespace" do
        probe = admin_action("Admin::Events::ShowAction") { def perform = render(json: {policy: policy(event).class.name}) }
        expect(invoke.call(probe, {id: ours.id}, as_api(admin)).body["policy"]).to eq("Admin::EventPolicy")
      end

      it "keeps a policy it names itself, as Pundit's policy_class: does" do
        chosen = admin_action("Admin::Events::ShowAction") do
          def perform
            authorize(event, :destroy?, policy_class: EventPolicy)
            render :show
          end
        end
        expect { invoke.call(chosen, {id: ours.id}, as_api(admin)) }.to be_refused.with(:forbidden)
      end
    end

    context "when the namespace has no policy" do
      it "fails closed, as Pundit does, and rails actions:check names the policy to add" do
        expect(list.policy_class).to be_nil
        expect { invoke.call(list, {}, as_api(manager)) }.to raise_error(Pundit::NotDefinedError, /Admin::EventPolicy/)
        expect(Saltbox::Actions::Registry.problems(list).join).to include("add Admin::EventPolicy")
      end
    end

    it "names a reference field whose records would be picked through a namespaced scope that does not exist" do
      stub_const("Admin::EventPolicy", Class.new {
        def initialize(user, record) = @user = user
        def update? = true
        def permitted_attributes = %i[title parent_id]
      })
      expect(Saltbox::Actions::Registry.problems(update)).to eq(["parent picks from Event records through Admin::EventPolicy::Scope, " \
        "which does not exist: add it, or declare policy_namespace (see the README)"])
    end

    it "takes a declared namespace in place of the one the class gives" do
      stub_const("Staff::EventPolicy", admin_event_policy)
      list.policy_namespace :staff
      expect(list.policy_class).to eq(Staff::EventPolicy)
      list.policy_namespace false
      expect(list.policy_class).to eq(EventPolicy)
    end

    context "with the modules around an action" do
      let(:base) { ApplicationAction }
      let(:admin_policy) { admin_event_policy }
      let(:public_policy) { EventPolicy }
      let(:missing_policy) { Pundit::NotDefinedError }

      it_behaves_like "the modules around an action"
    end

    it "keeps the model's own policy for an action in its model's namespace" do
      expect(Events::ListAction.policy_class).to eq(EventPolicy)
      expect(Billing::Invoices::ListAction.policy_class).to eq(Billing::InvoicePolicy)
      expect(Reports::CountEventsAction.policy_namespace).to eq([])
    end
  end

  describe "with ActionPolicy" do
    before do
      ActionPolicy::LookupChain::NamespaceCache.clear
      stub_const("EventPolicy", Class.new(ActionPolicy::Base) {
        authorize :user
        def index? = user.can?("events.view")
        def show? = index?
        def update? = user.can?("events.manage")
        def permitted_attributes = %i[title]
        relation_scope { |relation| relation.where(org_id: user.org_id) }
      })
      stub_const("PolicyAction", Class.new(Saltbox::Actions::Base) { include Saltbox::Actions::Authorization::ActionPolicy })
    end

    after { ActionPolicy::LookupChain::NamespaceCache.clear }

    def admin_policy
      Class.new(ActionPolicy::Base) {
        authorize :user
        def index? = user.can?("events.admin")
        def show? = index?
        def update? = index?
        def export? = index?
        def permitted_attributes = %i[title notes parent_id]
        relation_scope { |relation| relation }
      }
    end

    def policy_action(name, &body) = stub_const(name, Class.new(PolicyAction, &body))

    let(:list) do
      policy_action("Admin::Events::ListAction") {
        def perform
          @events = policy_scope(Event).order(:id)
          render :index
        end
      }
    end

    let(:show) { policy_action("Admin::Events::ShowAction") { def perform = render(:show) } }

    let(:update) do
      policy_action("Admin::Events::UpdateAction") {
        def perform
          event.update!(permitted_attributes(event))
          render :show
        end
      }
    end

    it "asks the namespace's policy" do
      stub_const("Admin::EventPolicy", admin_policy)
      expect(list.policy_class).to eq(Admin::EventPolicy)
      expect { invoke.call(list, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(invoke.call(list, {}, as_api(admin)).body.dig("data", "events").pluck("title")).to eq(%w[AGM Elsewhere])
    end

    it "never falls back to the model's own policy, and rails actions:check names the one to add" do
      expect(list.policy_class).to be_nil
      expect { invoke.call(list, {}, as_api(manager)) }.to raise_error(ActionPolicy::NotFound)
      expect(Saltbox::Actions::Registry.problems(list).join).to include("add Admin::EventPolicy")
    end

    context "when the model names its own policy" do
      before { stub_const("Admin::EventPolicy", admin_policy) }

      let(:model_policy) { EventPolicy }
      let(:missing_policy) { ActionPolicy::NotFound }

      it_behaves_like "a model that names its own policy", :model
      it_behaves_like "a model that names its own policy", :record
    end

    it "looks a model's policy_name up inside the namespace, never outside it" do
      stub_const("Admin::EventPolicy", admin_policy)
      Event.define_singleton_method(:policy_name) { "EventPolicy" }
      expect(list.policy_class).to eq(Admin::EventPolicy)
      Event.define_singleton_method(:policy_name) { "Elsewhere::EventPolicy" }
      stub_const("Elsewhere::EventPolicy", EventPolicy)
      ActionPolicy::LookupChain::NamespaceCache.clear
      expect(list.policy_class).to be_nil
      expect { invoke.call(list, {}, as_api(manager)) }.to raise_error(ActionPolicy::NotFound)
    ensure
      Event.singleton_class.remove_method(:policy_name)
    end

    it "keeps a policy the action's own code names with with:" do
      stub_const("Admin::EventPolicy", admin_policy)
      chosen = policy_action("Admin::Events::ShowAction") {
        def perform
          authorize(event, :update?, with: Class.new(EventPolicy) { def update? = false })
          render :show
        end
      }
      expect { invoke.call(chosen, {id: ours.id}, as_api(admin)) }.to be_refused.with(:forbidden)
    end

    context "with the modules around an action" do
      let(:base) { PolicyAction }
      let(:public_policy) { EventPolicy }
      let(:missing_policy) { ActionPolicy::NotFound }

      it_behaves_like "the modules around an action"
    end

    it "keeps its own policy when an app caches policies per thread" do
      stub_const("Admin::EventPolicy", admin_policy)
      PolicyAction.prepend(ActionPolicy::Behaviours::ThreadMemoized)
      was_enabled = ActionPolicy::PerThreadCache.enabled?
      ActionPolicy::PerThreadCache.enabled = true
      public_show = policy_action("Staff::Events::ShowAction") {
        policy_namespace false
        def perform = render(:show)
      }
      invoke.call(public_show, {id: ours.id}, as_api(admin))
      invoke.call(update, {id: ours.id, notes: "Admin only"}, as_api(admin))
      expect(ours.reload.notes).to eq("Admin only")
    ensure
      ActionPolicy::PerThreadCache.enabled = was_enabled
      ActionPolicy::PerThreadCache.clear_all
    end
  end
end
