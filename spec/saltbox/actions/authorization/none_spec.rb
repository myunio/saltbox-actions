# An app with no authorization library: a base class with no adapter allows
# every action and asks for no policy at boot, and the README's plain-model
# adapter plugs the app's own rules in.
RSpec.describe Saltbox::Actions::Authorization::None do
  # A model with no policy of any library.
  before do
    stub_const("Gathering", Class.new(ApplicationRecord) {
      self.table_name = "events"
      belongs_to :parent, class_name: "Gathering", optional: true
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

  it "asks for no policy, rule or rule name, at boot or in rails actions:check" do
    with_settings(require_area: false) do
      archive = action("Gatherings::ArchiveAction") do
        kind :change
        attribute :id
        connections :confirm
      end
      totals = action("Gatherings::ShowTotalsAction") { connections :allowed }
      expect(Saltbox::Actions::Registry.problems(archive)).to eq([])
      expect(Saltbox::Actions::Registry.problems(totals)).to eq([])
      create = action("Gatherings::CreateAction") { connections :allowed }
      expect(Saltbox::Actions::Registry.problems(create)).to eq([])
      expect(Saltbox::Actions::Registry.problems(create, declared_only: true)).to eq([])
    end
  end

  it "runs every action, for every person, with no authorize or policy_scope" do
    gathering = Gathering.create!(org_id: 1, title: "AGM")
    rename = action("Gatherings::RenameAction") do
      kind :change
      attribute :id
      attribute :title, :string
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

  it "takes the model fields an action accepts, the same for every person, refusing any other as unknown" do
    gathering = Gathering.create!(org_id: 1, title: "AGM")
    retitle = action("Gatherings::UpdateAction") do
      accepts :title, :capacity, :parent

      def perform
        gathering.update!(permitted_attributes(gathering))
        render json: {title: gathering.title, capacity: gathering.capacity}
      end
    end
    with_settings(require_area: false) { expect(Saltbox::Actions::Registry.problems(retitle)).to eq([]) }
    expect(retitle.input_schema(as_screen(stranger))["properties"].keys).to eq(%w[id title capacity parent])
    parent = Gathering.create!(org_id: 1, title: "Conference")
    expect(invoke.call(retitle, {id: gathering.id, title: "Renamed", capacity: "40", parent: parent.id}, as_screen(stranger)).body)
      .to eq("title" => "Renamed", "capacity" => 40)
    expect(gathering.reload.parent).to eq(parent)
    expect { invoke.call(retitle, {id: gathering.id, notes: "x"}, as_screen(stranger)) }.to have_field_errors(:notes)
  end

  it "takes a model given to policy_scope as all its records" do
    open = action("Gatherings::ListAction") { connections :allowed }
    expect(open.new(actor: as_screen(stranger), params: nil).policy_scope(Gathering)).to be_a(ActiveRecord::Relation)
  end

  describe "the README's plain-model adapter" do
    # The adapter's module, read from the README's code block as written.
    def self.readme_adapter
      readme = File.read(File.expand_path("../../../../README.md", __dir__))
      block = readme[%r{```ruby\n# app/actions/application_action/model_authorization.rb\n(.*?)```}m, 1]
      block[/\Amodule ApplicationAction::ModelAuthorization\n.*?^end\n/m]
    end

    before do
      TOPLEVEL_BINDING.eval(self.class.readme_adapter, "README.md")
      stub_const("ModelAction", Class.new(Saltbox::Actions::Base) { include ApplicationAction::ModelAuthorization })
    end

    after { ApplicationAction.send(:remove_const, :ModelAuthorization) }

    # A person who may update only what they can see, and only as an editor.
    let(:person_class) { Struct.new(:id, :org_id, :editor) { def can?(rule, _record) = rule != :update? || editor } }
    let(:person) { person_class.new(10, 1, true) }
    let(:viewer) { person_class.new(11, 1, false) }

    let(:update) do
      action("Gatherings::UpdateAction", base: ModelAction) do
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
      action("Gatherings::ListAction", base: ModelAction) do
        connections :allowed
        def perform = render(json: {titles: policy_scope(Gathering).order(:id).pluck(:title)})
      end
    end

    let(:create) do
      action("Gatherings::CreateAction", base: ModelAction) do
        connections :confirm
        def perform
          @gathering = policy_scope(Gathering).new(permitted_attributes(Gathering))
          authorize @gathering
          @gathering.save!
          render json: {title: @gathering.title}, status: :created
        end
      end
    end

    it "creates with the model's fields, given the model class" do
      result = invoke.call(create, {title: "New", capacity: 12}, as_screen(person))
      expect(result.status).to eq(201)
      expect(Gathering.last.attributes.slice("title", "capacity", "org_id")).to eq("title" => "New", "capacity" => 12, "org_id" => 1)
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
