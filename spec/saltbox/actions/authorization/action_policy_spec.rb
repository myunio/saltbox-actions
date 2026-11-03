# Actions on the same Event model, authorized with ActionPolicy through
# ActionPolicies::EventPolicy (aliases and a default rule) instead of Pundit.
RSpec.describe Saltbox::Actions::Authorization::ActionPolicy do
  before do
    stub_const("PolicyAction", Class.new(Saltbox::Actions::Base) {
      include Saltbox::Actions::Authorization::ActionPolicy

      policy_namespace ActionPolicies
    })
  end

  def action(name, &body)
    Class.new(PolicyAction) do
      define_singleton_method(:name) { name }
      model Event
      class_eval(&body)
    end
  end

  let(:show) do
    action("Events::ShowAction") do
      agents :allowed
      def perform
        @event = policy_scope(Event).find(params[:id])
        authorize @event
        render :show
      end
    end
  end

  let(:update) do
    action("Events::UpdateAction") do
      agents :allowed
      def perform
        @event = policy_scope(Event).find(params[:id])
        authorize @event
        @event.update!(permitted_attributes(@event))
        render :show
      end
    end
  end

  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:invoke) { ->(klass, arguments, caller) { Saltbox::Actions::Invocation.call(action: klass, caller:, arguments:) } }

  it "finds the namespaced policy, and answers aliased and default rules" do
    expect(update.policy_class).to eq(ActionPolicies::EventPolicy)
    expect(show.policy_rule?(:show?)).to be(true)
    expect(update.policy_rule?(:update?)).to be(true)
    expect(update.policy_label).to eq("ActionPolicy")
  end

  it "asks the policy's rule for the person before any record is loaded" do
    expect(show.permitted?(reader)).to be(true)
    expect(update.permitted?(reader)).to be(false)
    expect(update.permitted?(manager)).to be(true)
  end

  it "runs through its relation scope and rule, answering forbidden and not found" do
    expect(invoke.call(show, {id: event.id.to_s}, as_screen(reader)).body.dig("data", "event", "title")).to eq("AGM")
    expect { invoke.call(update, {id: event.id.to_s, title: "X"}, as_screen(reader)) }.to be_refused.with(:forbidden)
    other = Event.create!(org_id: 2, title: "Elsewhere")
    expect { invoke.call(show, {id: other.id.to_s}, as_screen(manager)) }.to be_not_found
  end

  it "builds the input schema from the policy's permitted_attributes" do
    expect(update.input_schema["properties"].keys).to eq(%w[id title starts_on capacity status])
    invoke.call(update, {id: event.id.to_s, title: "Renamed"}, as_screen(manager))
    expect(event.reload.title).to eq("Renamed")
  end

  it "fails an action that never calls authorize or policy_scope" do
    unchecked = action("Events::ExportAction") do
      agents :allowed
      def perform = render(json: {})
    end
    expect { invoke.call(unchecked, {}, as_screen(manager)) }.to raise_error(Saltbox::Actions::AuthorizationNotPerformedError)
    unscoped = action("Events::ExportAction") do
      agents :allowed
      def perform
        authorize Event
        render(json: {})
      end
    end
    expect { invoke.call(unscoped, {}, as_screen(manager)) }.to raise_error(Saltbox::Actions::PolicyScopingNotPerformedError)
  end

  it "passes the same registry checks, through the adapter" do
    missing = action("Events::ArchiveAction") do
      kind :change
      agents :allowed
      policy_rule :archive?
    end
    expect(Saltbox::Actions::Registry.problems(missing)).to eq([])
    expect(Saltbox::Actions::Registry.problems(show)).to eq([])
  end

  it "refuses ActionPolicy's authorize macro, whose context the checks before perform would never see" do
    expect { Class.new(PolicyAction) { authorize :tenant, through: :current_tenant } }
      .to raise_error(ArgumentError, /authorize :tenant would reach only the checks inside perform: override authorization_context_for/)
  end

  it "gives the policy the same context everywhere: the role check, the schema, authorize, scopes and references" do
    stub_const("TenantPolicies::EventPolicy", Class.new(ActionPolicy::Base) {
      authorize :user
      authorize :tenant

      def index? = user.can?("events.view")
      def update? = user.can?("events.manage")
      def permitted_attributes = %i[title parent_id]

      relation_scope { |relation| relation.where(org_id: tenant) }
    })
    tenant_action = Class.new(PolicyAction) do
      policy_namespace TenantPolicies
      def self.authorization_context_for(user) = {user:, tenant: user.org_id}
    end
    update = Class.new(tenant_action) do
      def self.name = "Events::UpdateAction"
      agents :allowed
      def perform
        event.update!(permitted_attributes(event))
        render :show
      end
    end
    hidden = Event.create!(org_id: 2, title: "Elsewhere")
    expect(update.input_schema(as_screen(manager))["properties"].keys).to eq(%w[id title parent])
    expect { invoke.call(update, {id: event.id, parent: hidden.id}, as_screen(manager)) }.to have_field_errors(:parent)
    expect { invoke.call(update, {id: hidden.id, title: "Mine"}, as_screen(manager)) }.to be_not_found
    invoke.call(update, {id: event.id, title: "Annual meeting"}, as_screen(manager))
    expect(event.reload.title).to eq("Annual meeting")
  end
end
