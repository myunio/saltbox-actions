# Base#resolve_reference: a field that names a record, by id or, for a
# lookup list (Configuration#lookup_lists), by name.
RSpec.describe "Resolving a reference" do
  let(:config) { Saltbox::Actions.config }
  let(:pick) do
    Class.new(ApplicationAction) do
      def self.name = "Events::PickAction"
      kind :read
      policy_rule :show?
      attribute :target, :string
      attribute :value, :string
      attribute :field, :string

      def perform
        skip_authorization
        skip_policy_scope
        render json: {"id" => resolve_reference(target.constantize, value, field: field || "kind")}
      end
    end
  end
  let(:resolve) do
    ->(model, value, caller: as_screen(manager), field: nil) {
      Saltbox::Actions::Invocation.call(action: pick, caller:, arguments: {target: model.name, value:, field:}.compact).body["id"]
    }
  end

  around do |example|
    original = config.lookup_lists
    config.lookup_lists = %w[EventKind]
    example.run
  ensure
    config.lookup_lists = original
  end

  it "finds a lookup list entry by id or by its name, ignoring case and the spaces around it" do
    agm = EventKind.create!(name: "Annual meeting")
    EventKind.create!(name: "Picnic")
    expect(resolve.call(EventKind, agm.id.to_s)).to eq(agm.id)
    expect(resolve.call(EventKind, "  annual MEETING ")).to eq(agm.id)
  end

  it "refuses an unknown name with the names that would work, and an ambiguous one with each match" do
    EventKind.create!(name: "Picnic")
    EventKind.create!(name: "AGM")
    expect { resolve.call(EventKind, "Dance") }.to raise_error(Saltbox::Actions::Error::ValidationFailed) { |error|
      expect(error.message).to eq("Kind isn't one of the event kinds")
      expect(error.errors).to eq("kind" => ["must be one of: AGM, Picnic"])
    }
    I18n.backend.store_translations(:en, actions: {errors: {not_in_lookup_list: "isn't one of the club's %{plural}"}})
    expect { resolve.call(EventKind, "Dance") }.to raise_error(Saltbox::Actions::Error::ValidationFailed, "Kind isn't one of the club's event kinds")
    I18n.backend.reload!
    twin = EventKind.create!(name: "picnic")
    expect { resolve.call(EventKind, "Picnic") }.to raise_error(Saltbox::Actions::Error::ValidationFailed, /matches more than one: .*\(#{twin.id}\)/)
  end

  it "refuses a reference inside a list under its path, naming only the field in the message" do
    EventKind.create!(name: "Picnic")
    expect { resolve.call(EventKind, "Dance", field: "events.1.kind") }.to raise_error(Saltbox::Actions::Error::ValidationFailed) { |error|
      expect(error.message).to eq("Kind isn't one of the event kinds")
      expect(error.errors).to eq("events.1.kind" => ["must be one of: Picnic"])
    }
  end

  it "finds any other record by id only, through the person's policy scope" do
    ours = Event.create!(org_id: 1, title: "AGM")
    theirs = Event.create!(org_id: 2, title: "Theirs")
    expect(resolve.call(Event, ours.id.to_s)).to eq(ours.id)
    expect { resolve.call(Event, "AGM") }.to raise_error(Saltbox::Actions::Error::ValidationFailed, "Kind isn't a event you can see")
    expect { resolve.call(Event, theirs.id.to_s) }.to raise_error(Saltbox::Actions::Error::ValidationFailed, "Kind isn't a event you can see")
  end
end
