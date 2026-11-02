RSpec.describe Saltbox::Actions::Schema do
  it "takes a create's fields from the policy, typed from the columns, requiring those with no default" do
    schema = Event::CreateAction.input_schema
    expect(schema["properties"].keys).to eq(%w[title starts_on capacity status parent notes])
    expect(schema["properties"]["title"]).to eq("type" => "string", "maxLength" => 120, "description" => "The event's name.")
    expect(schema["properties"]["starts_on"]).to eq("type" => %w[string null], "format" => "date")
    expect(schema["properties"]["status"]).to include("type" => "string", "enum" => %w[draft published cancelled])
    expect(schema["properties"]["parent"]).to eq("type" => %w[string null])
    expect(schema["required"]).to eq(%w[title])
    expect(schema["additionalProperties"]).to be(false)
  end

  it "gives every caller the same schema, asked of the schema principal, who may set every field" do
    expect(Event::CreateAction.input_schema["properties"]).to have_key("notes")
    expect(Event::UpdateAction.input_schema["required"]).to eq(%w[id])
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
    expect(properties["amount"]).to eq("type" => %w[number string null])
    expect(properties["mode"]).to eq("type" => "string", "enum" => %w[merge replace])
    expect(action.input_schema["required"]).to eq(%w[mode])
  end
end
