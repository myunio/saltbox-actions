RSpec.describe Saltbox::Actions::Schema do
  it "takes a create's fields from the policy, typed from the columns, requiring those with no default" do
    schema = Events::CreateAction.input_schema
    expect(schema["properties"].keys).to eq(%w[title starts_on capacity price featured doors_open_at status parent notes])
    expect(schema["properties"]["title"]).to eq("type" => "string", "maxLength" => 120, "description" => "The event's name.")
    expect(schema["properties"]["starts_on"]).to eq("type" => %w[string null], "format" => "date")
    expect(schema["properties"]["status"]).to include("type" => "string", "enum" => %w[draft published cancelled])
    expect(schema["properties"]["price"]).to eq("type" => %w[number string null], "pattern" => "^[+-]?(\\d+\\.?\\d*|\\.\\d+)$")
    expect(schema["properties"]["parent"]).to eq("type" => %w[string integer null])
    expect(schema["required"]).to eq(%w[title])
    expect(schema["additionalProperties"]).to be(false)
  end

  it "builds the catalog's schema, with no caller, for the schema user" do
    expect(Events::CreateAction.input_schema["properties"]).to have_key("notes")
    expect(Events::UpdateAction.input_schema["required"]).to eq(%w[id])
  end

  context "with a caller" do
    let(:note_keeper) { User.new(id: 9, permissions: %w[events.view events.manage events.notes]) }
    let(:fields) { ->(user) { Events::CreateAction.input_schema(as_screen(user))["properties"].keys } }

    it "lists the fields the policy permits that caller, never another caller's" do
      expect(fields.call(manager)).not_to include("notes")
      expect(fields.call(note_keeper)).to include("notes")
      expect(fields.call(manager)).not_to include("notes")
      expect(Saltbox::Actions::AgentTools.find("add an event", as_mcp(manager))[:actions].find { it[:name] == "create_event" }[:input_schema]["properties"]).not_to have_key("notes")
      expect(Saltbox::Actions::Registry.catalog(as_screen(note_keeper)).find { it["name"] == "create_event" }.dig("input_schema", "properties")).to have_key("notes")
    end

    it "runs with a policy that needs a person, with no schema user set" do
      allow(ApplicationAction).to receive(:with_schema_user).and_yield(nil)
      expect { Events::CreateAction.input_schema }.to raise_error(NoMethodError)
      run = ->(user, arguments) { Saltbox::Actions::Invocation.call(action: "create_event", caller: as_screen(user), arguments:) }
      expect(run.call(note_keeper, {title: "AGM", notes: "Quorum is 12"}).status).to eq(201)
      expect(Event.last.notes).to eq("Quorum is 12")
      expect { run.call(manager, {title: "AGM", notes: "x"}) }.to be_refused.with(:forbidden)
      expect { run.call(manager, {title: "AGM", notes: "x"}) }.to raise_error(Saltbox::Actions::Error::Forbidden, "You can't change notes.")
    end

    it "refuses every field the caller may not set, once, as ForbiddenFields, which the app may rescue" do
      invocation = -> { Saltbox::Actions::Invocation.call(action: "create_event", caller: as_screen(manager), arguments: {title: "AGM", notes: "x", nope: 1}) }
      expect { invocation.call }.to raise_error(Saltbox::Actions::Error::ForbiddenFields) { |error|
        expect(error).to have_attributes(code: "forbidden", status: :forbidden, fields: %w[notes], message: "You can't change notes.",
          errors: {"notes" => ["you can't change this"]})
      }
      seen = []
      refusal = proc do |error|
        seen << [current_user, self.class, error.fields]
        raise Saltbox::Actions::Error::Forbidden, "Not yours to change."
      end
      with_rescue_from(Saltbox::Actions::Error::ForbiddenFields, refusal) do
        expect { invocation.call }.to raise_error(Saltbox::Actions::Error::Forbidden, "Not yours to change.")
      end
      expect(seen).to eq([[manager, Events::CreateAction, %w[notes]]])
    end

    it "words the refusal with the app's actions.errors.forbidden_fields and forbidden_field" do
      I18n.backend.store_translations(:en, actions: {errors: {forbidden_fields: "Ask an organizer about %{fields}.", forbidden_field: "organizers only"}})
      expect(Saltbox::Actions::Error::ForbiddenFields.new(fields: %w[notes capacity])).to have_attributes(message: "Ask an organizer about notes and capacity.",
        errors: {"notes" => ["organizers only"], "capacity" => ["organizers only"]})
    ensure
      I18n.reload!
    end

    it "answers a field the policy refuses for the record as ForbiddenFields too" do
      event = Event.create!(org_id: 1, title: "AGM")
      action = Class.new(Events::UpdateAction) do
        def self.name = "Events::UpdateAction"
        private def permitted_attribute_names(record) = super - %w[capacity title]
      end
      action.rescue_from(Saltbox::Actions::Error::ForbiddenFields) { |error| raise Saltbox::Actions::Error::Forbidden, "#{current_user.id}/#{self.class.name}: #{error.fields.join(",")}" }
      run = -> { Saltbox::Actions::Invocation.call(action: action, caller: as_screen(manager), arguments: {id: event.id.to_s, title: "Picnic", capacity: 5, featured: true}) }
      expect { run.call }.to raise_error(Saltbox::Actions::Error::Forbidden, "1/Events::UpdateAction: title,capacity")
      expect(event.reload.title).to eq("AGM")
    end

    it "keeps the gem's own refusal where there is no caller" do
      checker = Saltbox::Actions::Arguments.new({"properties" => {}}, forbidden: ->(_) { true })
      expect { checker.validate!(notes: "x") }.to raise_error(Saltbox::Actions::Error::Forbidden, "You can't change notes.")
    end
  end

  it "types attributes, including lists of records capped at the configured size" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::ImportAction"
      kind :change
      attribute :rows, :array, of: {title: :string, capacity: :integer}
      attribute :amount, :decimal, nullable: true
      attribute :starts_at, :datetime
    end
    properties = action.input_schema["properties"]
    expect(properties["rows"]).to include("type" => "array", "maxItems" => 50)
    expect(properties["rows"]["items"]["properties"]["capacity"]).to eq("type" => %w[integer null])
    expect(properties["amount"]).to include("type" => %w[number string null])
    expect(properties["starts_at"]).to eq("type" => "string", "format" => "date-time")
    expect { Class.new(ApplicationAction) { attribute :page, :integer, minimum: 1 } }
      .to raise_error(ArgumentError, "page takes no minimum: validations shape an attribute's schema")
    %i[params errors authorize id].each do |name|
      expect { Class.new(ApplicationAction) { attribute name, :string } }.to raise_error(ArgumentError, "#{name} is a method every action has: name the attribute another way")
    end
    bounded = Class.new(ApplicationAction) do
      def self.name = "Events::ExportAction"
      attribute :label, :string
      validates :label, length: {minimum: 2, maximum: -> { 5 }}
      attribute :style, :string
      validates :style, inclusion: {in: %w[short long]}, allow_blank: true
    end
    expect(bounded.input_schema["properties"]).to include("label" => {"type" => "string", "minLength" => 2},
      "style" => {"type" => "string", "enum" => ["short", "long", ""]})
    export = Class.new(ApplicationAction) do
      def self.name = "Events::ExportAction"
      attribute :format, :string
    end
    expect(export.input_schema["properties"]).to have_key("format")
  end

  it "refuses an attribute or an item's field whose name has a dot, since errors name a field by its dotted path" do
    expect { Class.new(ApplicationAction) { attribute :"rows.title", :string } }
      .to raise_error(ArgumentError, "rows.title has a dot: an error names a field by its path, joined with dots")
    expect { Class.new(ApplicationAction) { attribute :rows, :array, of: {"seat.row": :string} } }
      .to raise_error(ArgumentError, "seat.row has a dot: an error names a field by its path, joined with dots")
  end

  it "shapes an attribute's schema with the validations that always run" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::ImportAction"
      kind :change
      attribute :mode, :string
      attribute :note, :string
      attribute :copies, :integer, default: 1
      attribute :tags, :array
      attribute :reason, :string
      validates :mode, presence: true, inclusion: {in: %i[merge replace]}
      validates :note, length: {in: 2..40}
      validates :copies, numericality: {greater_than: 0, less_than_or_equal_to: 10}
      validates :tags, length: {maximum: 3}
      validates :reason, presence: true, if: -> { mode == "replace" }
    end
    properties = action.input_schema["properties"]
    expect(properties["mode"]).to eq("type" => "string", "enum" => %w[merge replace])
    expect(properties["note"]).to eq("type" => "string", "minLength" => 2, "maxLength" => 40)
    expect(properties["copies"]).to eq("type" => "integer", "exclusiveMinimum" => 0, "maximum" => 10, "default" => 1)
    expect(properties["tags"]).to include("maxItems" => 3)
    expect(properties["reason"]).to eq("type" => "string")
    expect(action.input_schema["required"]).to eq(%w[mode])
  end
end
