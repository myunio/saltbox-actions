RSpec.describe Saltbox::Actions::Schema do
  it "takes a create's fields from the policy, typed from the columns, requiring those with no default" do
    schema = Event::CreateAction.input_schema
    expect(schema["properties"].keys).to eq(%w[title starts_on capacity price featured doors_open_at status parent notes])
    expect(schema["properties"]["title"]).to eq("type" => "string", "maxLength" => 120, "description" => "The event's name.")
    expect(schema["properties"]["starts_on"]).to eq("type" => %w[string null], "format" => "date")
    expect(schema["properties"]["status"]).to include("type" => "string", "enum" => %w[draft published cancelled])
    expect(schema["properties"]["price"]).to eq("type" => %w[number string null], "pattern" => "^[+-]?(\\d+\\.?\\d*|\\.\\d+)$")
    expect(schema["properties"]["parent"]).to eq("type" => %w[string integer null])
    expect(schema["required"]).to eq(%w[title])
    expect(schema["additionalProperties"]).to be(false)
  end

  it "builds the catalogue's schema, with no caller, for the schema principal" do
    expect(Event::CreateAction.input_schema["properties"]).to have_key("notes")
    expect(Event::UpdateAction.input_schema["required"]).to eq(%w[id])
  end

  context "with a caller" do
    let(:note_keeper) { Account.new(id: 9, permissions: %w[events.view events.manage events.notes]) }
    let(:fields) { ->(account) { Event::CreateAction.input_schema(as_screen(account))["properties"].keys } }

    it "lists the fields the policy permits that caller, never another caller's" do
      expect(fields.call(manager)).not_to include("notes")
      expect(fields.call(note_keeper)).to include("notes")
      expect(fields.call(manager)).not_to include("notes")
      expect(Saltbox::Actions::FrontDoor.find("add an event", as_mcp(manager))[:actions].find { it[:name] == "create_event" }[:arguments]["properties"]).not_to have_key("notes")
      expect(Saltbox::Actions::Registry.catalogue(as_screen(note_keeper)).find { it["name"] == "create_event" }.dig("input_schema", "properties")).to have_key("notes")
    end

    it "runs with a policy that needs a person, with no schema principal set" do
      allow(Saltbox::Actions.config).to receive(:schema_principal).and_return(nil)
      expect { Event::CreateAction.input_schema }.to raise_error(NoMethodError)
      run = ->(account, arguments) { Saltbox::Actions::Invocation.call(name: "create_event", caller: as_screen(account), arguments:) }
      expect(run.call(note_keeper, {title: "AGM", notes: "Quorum is 12"}).status).to eq(201)
      expect(Event.last.notes).to eq("Quorum is 12")
      expect { run.call(manager, {title: "AGM", notes: "x"}) }.to be_refused.with(:forbidden)
      expect { run.call(manager, {title: "AGM", notes: "x"}) }.to raise_error(Saltbox::Actions::Error::Forbidden, "You can't change notes.")
    end

    it "refuses every field the caller may not set, once, through on_forbidden_fields" do
      seen = []
      refusal = ->(caller, action, fields) {
        seen << [caller.account, action, fields]
        Saltbox::Actions::Error::Forbidden.new("Not yours to change.")
      }
      allow(Saltbox::Actions.config).to receive(:on_forbidden_fields).and_return(refusal)
      invocation = -> { Saltbox::Actions::Invocation.call(name: "create_event", caller: as_screen(manager), arguments: {title: "AGM", notes: "x", nope: 1}) }
      expect { invocation.call }.to raise_error(Saltbox::Actions::Error::Forbidden, "Not yours to change.")
      expect(seen).to eq([[manager, Event::CreateAction, %w[notes]]])
    end

    it "answers a field the policy refuses for the record through on_forbidden_fields too" do
      event = Event.create!(org_id: 1, title: "AGM")
      action = Class.new(Event::UpdateAction) do
        def self.name = "Event::UpdateAction"
        private def permitted_attribute_names(record) = super - %w[capacity title]
      end
      refusal = ->(caller, action, fields) { Saltbox::Actions::Error::Forbidden.new("#{caller.account.id}/#{action.name}: #{fields.join(",")}") }
      allow(Saltbox::Actions.config).to receive(:on_forbidden_fields).and_return(refusal)
      run = -> { Saltbox::Actions::Invocation.call(name: action, caller: as_screen(manager), arguments: {id: event.id.to_s, title: "Picnic", capacity: 5, featured: true}) }
      expect { run.call }.to raise_error(Saltbox::Actions::Error::Forbidden, "1/Event::UpdateAction: title,capacity")
      expect(event.reload.title).to eq("AGM")
    end

    it "keeps the gem's own refusal where there is no caller" do
      allow(Saltbox::Actions.config).to receive(:on_forbidden_fields).and_return(->(*) { raise "not called" })
      checker = Saltbox::Actions::Arguments.new({"properties" => {}}, forbidden: ->(_) { true })
      expect { checker.validate!(notes: "x") }.to raise_error(Saltbox::Actions::Error::Forbidden, "You can't change notes.")
    end
  end

  it "types declared arguments, including lists of records capped at the configured size" do
    action = Class.new(ApplicationAction) do
      def self.name = "Event::ImportAction"
      kind :change
      connections :allowed
      argument :rows, :array, of: {title: :string, capacity: :integer}
      argument :amount, :decimal, nullable: true
      argument :mode, :string, enum: %i[merge replace], required: true
    end
    properties = action.input_schema["properties"]
    expect(properties["rows"]).to include("type" => "array", "maxItems" => 50)
    expect(properties["rows"]["items"]["properties"]["capacity"]).to eq("type" => %w[integer null])
    expect(properties["amount"]).to include("type" => %w[number string null])
    expect(properties["mode"]).to eq("type" => "string", "enum" => %w[merge replace])
    expect(action.input_schema["required"]).to eq(%w[mode])
  end
end
