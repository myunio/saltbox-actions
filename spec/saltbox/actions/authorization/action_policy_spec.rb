# Actions on the same Event model, authorized with ActionPolicy through
# ActionPolicies::EventPolicy (aliases and a default rule) instead of Pundit.
RSpec.describe Saltbox::Actions::Authorization::ActionPolicy do
  before do
    stub_const("PolicyAction", Class.new(Saltbox::Actions::Base) {
      include Saltbox::Actions::Authorization::ActionPolicy

      def self.policy_namespace = ActionPolicies
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
    action("Policies::ShowAction") do
      connections :allowed
      def perform
        @event = policy_scope(Event).find(params[:id])
        authorize @event
        render :show
      end
    end
  end

  let(:update) do
    action("Policies::UpdateAction") do
      connections :allowed
      def perform
        @event = policy_scope(Event).find(params[:id])
        authorize @event
        @event.update!(permitted_attributes(@event))
        render :show
      end
    end
  end

  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:invoke) { ->(klass, arguments, caller) { Saltbox::Actions::Invocation.call(name: klass, caller:, arguments:) } }

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
    unchecked = action("Policies::ExportAction") do
      connections :allowed
      def perform = render(json: {})
    end
    expect { invoke.call(unchecked, {}, as_screen(manager)) }.to raise_error(Saltbox::Actions::AuthorizationNotPerformedError)
    unscoped = action("Policies::ExportAction") do
      connections :allowed
      def perform
        authorize Event
        render(json: {})
      end
    end
    expect { invoke.call(unscoped, {}, as_screen(manager)) }.to raise_error(Saltbox::Actions::PolicyScopingNotPerformedError)
  end

  it "passes the same registry checks, through the adapter" do
    missing = action("Policies::ArchiveAction") do
      kind :change
      connections :allowed
      authorize :archive?
    end
    expect(Saltbox::Actions::Registry.problems(missing)).to eq([])
    expect(Saltbox::Actions::Registry.problems(show)).to eq([])
  end
end
