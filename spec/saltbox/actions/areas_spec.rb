# Configuration#areas and Saltbox::Actions::Areas.
RSpec.describe Saltbox::Actions::Areas do
  let(:config) { Saltbox::Actions.config }
  let(:areas) do
    {"events" => {models: %w[Event EventKind], metadata_models: %w[Event], read_action: "list_events"},
     "billing" => {models: %w[Billing::Invoice]}}
  end

  around { |example| with_settings(areas:) { example.run } }

  it "lists the areas in the app's order, and the area of each model" do
    expect(described_class.names).to eq(%w[events billing])
    expect(described_class.area_for("EventKind")).to eq("events")
    expect(described_class.area_for("Unmapped")).to be_nil
    expect(described_class.for_model!("Billing::Invoice")).to eq("billing")
    expect { described_class.for_model!("Unmapped") }.to raise_error(ArgumentError, /No area maps Unmapped/)
  end

  it "answers each action's area from its model's" do
    expect(Events::UpdateAction.area).to eq("events")
    expect(Billing::Invoices::ListAction.area).to eq("billing")
    with_settings(areas: {}) { expect(Events::UpdateAction.area).to be_nil }
  end

  it "lets an area's readers see the record of only its metadata models" do
    expect(described_class.metadata?("events", "Event")).to be true
    expect(described_class.metadata?("events", "EventKind")).to be false
    expect(described_class.metadata?("billing", "Billing::Invoice")).to be false
    expect(described_class.metadata?("unknown", "Event")).to be false
  end

  it "admits a person to an area through its read action, inside within" do
    expect(Saltbox::Actions.within(as_screen(manager)) { described_class.readable?("events", it) }).to be true
    expect(Saltbox::Actions.within(as_screen(stranger)) { described_class.readable?("events", it) }).to be false
    expect(Saltbox::Actions.within(as_screen(manager)) { described_class.readable?("billing", it) }).to be false
  end

  it "takes only models, metadata_models and read_action" do
    expect { config.areas = {"events" => {models: %w[Event], reads: "list_events"}} }.to raise_error(ArgumentError, /not reads/)
  end

  describe ".validate!, which rails actions:check runs" do
    it "passes the dummy app's areas" do
      expect { described_class.validate! }.not_to raise_error
    end

    it "refuses a model in two areas, and metadata models an area does not map" do
      config.areas = areas.merge("more" => {models: %w[Event]})
      expect { described_class.validate! }.to raise_error(ArgumentError, /maps Event more than once/)
      config.areas = {"events" => {models: %w[EventKind], metadata_models: %w[Event]}}
      expect { described_class.validate! }.to raise_error(ArgumentError, /metadata_models it does not map: Event/)
    end

    it "refuses an area whose models destroy a tracked model no area maps, at any depth" do
      stub_const("Billing::Ledger", Class.new(ApplicationRecord) {
        self.table_name = "billing_invoices"
        has_many :invoices, class_name: "Billing::Invoice", foreign_key: :org_id, dependent: :destroy
      })
      stub_const("Billing::Book", Class.new(ApplicationRecord) {
        self.table_name = "billing_invoices"
        has_many :ledgers, class_name: "Billing::Ledger", foreign_key: :org_id, dependent: :destroy
        has_many :events, class_name: "Event", foreign_key: :org_id, dependent: :destroy
      })
      config.areas = {"billing" => {models: %w[Billing::Book]}}
      expect { described_class.validate! }.to raise_error(ArgumentError,
        "Map Billing::Ledger, Billing::Invoice, Event to an area in config.areas: an area's models destroy them")
      config.areas = {"billing" => {models: %w[Billing::Book Billing::Ledger Billing::Invoice]}, "events" => {models: %w[Event]}}
      expect { described_class.validate! }.not_to raise_error
    end
  end
end
