# An app with no authorization library: a base class with no adapter allows
# every action and asks for no policy at boot, and the README's plain-model
# adapter plugs the app's own rules in.
RSpec.describe Saltbox::Actions::Authorization::None do
  # A model with no policy of any library.
  before do
    stub_const("Gathering", Class.new(ApplicationRecord) {
      self.table_name = "events"
      scope :visible_to, ->(user) { where(org_id: user.org_id) }
      def self.writable_attributes(_user) = %w[title capacity]
    })
    stub_const("OpenAction", Class.new(Saltbox::Actions::Base))
  end

  def action(name, base: OpenAction, &body)
    Class.new(base) do
      define_singleton_method(:name) { name }
      class_eval(&body)
    end
  end

  let(:invoke) { ->(klass, arguments, caller) { Saltbox::Actions::Invocation.call(name: klass, caller:, arguments:) } }

  it "asks for no policy, rule or rule name at boot" do
    with_settings(require_area: false) do
      archive = action("Gathering::ArchiveAction") do
        kind :change
        argument :id
        connections :confirm
      end
      totals = action("Gathering::ShowTotalsAction") { connections :allowed }
      expect(Saltbox::Actions::Registry.problems(archive)).to eq([])
      expect(Saltbox::Actions::Registry.problems(totals)).to eq([])
    end
  end

  it "runs every action, for every person, with no authorize or policy_scope" do
    gathering = Gathering.create!(org_id: 1, title: "AGM")
    rename = action("Gathering::RenameAction") do
      kind :change
      argument :id
      argument :title, :string
      connections :allowed
      def perform
        Gathering.find(params[:id]).update!(title: params[:title])
        head :no_content
      end
    end
    expect(rename.permitted?(stranger)).to be(true)
    invoke.call(rename, {id: gathering.id.to_s, title: "Renamed"}, as_screen(stranger))
    expect(gathering.reload.title).to eq("Renamed")
  end

  it "takes a model given to policy_scope as all its records" do
    open = action("Gathering::ListAction") { connections :allowed }
    expect(open.new(actor: as_screen(stranger), params: nil).policy_scope(Gathering)).to be_a(ActiveRecord::Relation)
  end

  describe "the README's plain-model adapter" do
    before do
      stub_const("ModelAuthorization", Module.new {
        extend ActiveSupport::Concern

        const_set(:NotAllowed, Class.new(StandardError))

        class_methods do
          def permitted?(user) = user.present?

          def permitted_attribute_names_for(user, record) = record.class.writable_attributes(user)

          def authorization_errors = [ModelAuthorization::NotAllowed]
        end

        def authorize(record, rule = nil)
          @authorized = true
          raise ModelAuthorization::NotAllowed unless account.can?(rule || self.class.policy_query, record)
          record
        end

        def policy_scope(scope)
          @scoped = true
          scope.visible_to(account)
        end

        def skip_authorization = @authorized = true

        def skip_policy_scope = @scoped = true

        def verify_authorized = @authorized || raise(Saltbox::Actions::AuthorizationNotPerformedError, "#{self.class.name} never called authorize")

        def verify_policy_scoped = @scoped || raise(Saltbox::Actions::PolicyScopingNotPerformedError, "#{self.class.name} never called policy_scope")

        def permitted_attribute_names(record) = self.class.permitted_attribute_names_for(account, record)

        def scoped_records(model) = model.visible_to(account)
      })
      stub_const("ModelAction", Class.new(Saltbox::Actions::Base) { include ModelAuthorization })
    end

    # A person who may update only what they can see, and only as an editor.
    let(:person_class) { Struct.new(:id, :org_id, :editor) { def can?(rule, _record) = rule != :update? || editor } }
    let(:person) { person_class.new(10, 1, true) }
    let(:viewer) { person_class.new(11, 1, false) }

    let(:update) do
      action("Gathering::UpdateAction", base: ModelAction) do
        connections :allowed
        def perform
          gathering = policy_scope(Gathering).find(params[:id])
          authorize gathering
          gathering.update!(permitted_attributes(gathering))
          render json: {title: gathering.title}
        end
      end
    end

    let(:list) do
      action("Gathering::ListAction", base: ModelAction) do
        connections :allowed
        def perform = render(json: {titles: policy_scope(Gathering).order(:id).pluck(:title)})
      end
    end

    it "takes the model's fields, checks the person's rule and answers a refusal as forbidden" do
      gathering = Gathering.create!(org_id: 1, title: "AGM")
      expect(update.input_schema["properties"].keys).to eq(%w[id title capacity])
      expect(invoke.call(update, {id: gathering.id.to_s, title: "Renamed"}, as_screen(person)).body).to eq("title" => "Renamed")
      expect { invoke.call(update, {id: gathering.id.to_s, title: "X"}, as_screen(viewer)) }.to be_refused.with(:forbidden)
    end

    it "lists through the scope alone, and hides other records as not found" do
      Gathering.create!(org_id: 1, title: "Ours")
      theirs = Gathering.create!(org_id: 2, title: "Theirs")
      expect(invoke.call(list, {}, as_screen(person)).body).to eq("titles" => ["Ours"])
      expect { invoke.call(update, {id: theirs.id.to_s, title: "X"}, as_screen(person)) }.to be_not_found
    end
  end
end
