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
      def permitted_attributes = %i[title notes parent_id]
    end.tap { it.const_set(:Scope, Class.new(EventPolicy::Scope) { def resolve = @scope.all }) }
  end

  def admin_action(name, &body)
    stub_const(name, Class.new(ApplicationAction, &body))
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
        relation_scope { |relation| relation.where(org_id: user.org_id) }
      })
      stub_const("PolicyAction", Class.new(Saltbox::Actions::Base) { include Saltbox::Actions::Authorization::ActionPolicy })
    end

    after { ActionPolicy::LookupChain::NamespaceCache.clear }

    let(:list) do
      stub_const("Admin::Events::ListAction", Class.new(PolicyAction) {
        def perform = render(json: {titles: policy_scope(Event).order(:id).pluck(:title)})
      })
    end

    it "asks the namespace's policy" do
      stub_const("Admin::EventPolicy", Class.new(ActionPolicy::Base) {
        authorize :user
        def index? = user.can?("events.admin")
        relation_scope { |relation| relation }
      })
      expect(list.policy_class).to eq(Admin::EventPolicy)
      expect { invoke.call(list, {}, as_api(manager)) }.to be_refused.with(:forbidden)
      expect(invoke.call(list, {}, as_api(admin)).body["titles"]).to eq(%w[AGM Elsewhere])
    end

    it "never falls back to the model's own policy, and rails actions:check names the one to add" do
      expect(list.policy_class).to be_nil
      expect { invoke.call(list, {}, as_api(manager)) }.to raise_error(ActionPolicy::NotFound)
      expect(Saltbox::Actions::Registry.problems(list).join).to include("add Admin::EventPolicy")
    end
  end
end
