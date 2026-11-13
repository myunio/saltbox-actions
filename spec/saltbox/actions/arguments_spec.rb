RSpec.describe Saltbox::Actions::Arguments do
  let(:checker) { described_class.for(Events::CreateAction) }

  it "refuses an argument the action does not take, naming it" do
    expect { checker.validate!(title: "AGM", colour: "red") }
      .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to eq(["colour"]) }
  end

  it "names a missing required field and a value of the wrong type" do
    expect { checker.validate!(capacity: "lots") }
      .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to contain_exactly("title", "capacity") }
  end

  it "treats null as left out unless the field may be null" do
    expect(checker.validate!(title: "AGM", status: nil, starts_on: nil)).to eq("title" => "AGM", "starts_on" => nil)
  end

  it "refuses input that is not an object" do
    expect { checker.validate!([1]) }.to raise_error(Saltbox::Actions::Error::ValidationFailed, "Arguments must be an object")
  end

  it "tells the developer to declare an id on an action that takes none" do
    expect { described_class.for(Events::ListAction).validate!(id: "1") }
      .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors["id"]).to eq(["list_events takes no id; declare attribute :id"]) }
  end

  describe "a list of records" do
    let(:checker) do
      payment = {"type" => "object", "properties" => {"amount" => {"type" => "number"}, "paid_on" => {"type" => "string", "format" => "date"}},
                 "required" => ["amount"], "additionalProperties" => false}
      described_class.new({"type" => "object", "properties" => {"payments" => {"type" => "array", "items" => payment}},
                           "required" => [], "additionalProperties" => false})
    end

    it "names a field of an item by the item's place in the list and the field, such as payments.1.paid_on" do
      expect { checker.validate!(payments: [{amount: 1}, {amount: 2, paid_on: "soon"}]) }
        .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to eq(["payments.1.paid_on"]) }
    end

    it "names an item's missing field and a field the item does not take by their paths" do
      expect { checker.validate!(payments: [{paid_on: "2026-11-01"}, {amount: 1, amount_cents: 100}]) }
        .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to contain_exactly("payments.0.amount", "payments.1.amount_cents") }
    end

    it "names a field in a list inside a list by its whole path, such as orders.0.lines.1.quantity" do
      line = {"type" => "object", "properties" => {"quantity" => {"type" => "integer"}}, "additionalProperties" => false}
      order = {"type" => "object", "properties" => {"lines" => {"type" => "array", "items" => line}}, "additionalProperties" => false}
      nested = described_class.new({"type" => "object", "properties" => {"orders" => {"type" => "array", "items" => order}},
                                    "required" => [], "additionalProperties" => false})
      expect { nested.validate!(orders: [{lines: [{quantity: 1}, {quantity: "two"}]}]) }
        .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to eq(["orders.0.lines.1.quantity"]) }
    end

    it "refuses a schema with a field whose name has a dot, whose errors would share a key with a nested field" do
      item = {"type" => "object", "properties" => {"b" => {"type" => "integer"}}}
      dotted = described_class.new({"type" => "object", "properties" => {"a.b" => {"type" => "integer"}, "a" => item},
                                    "required" => [], "additionalProperties" => false})
      expect { dotted.validate!({}) }.to raise_error(ArgumentError, "a.b has a dot: an error names a field by its path, joined with dots")
    end

    it "allows a field's default to hold a key with a dot, even when the default looks like a schema, since it is data" do
      settings = {"properties" => {"v1.2" => true}}
      schema = {"type" => "object", "properties" => {"settings" => {"type" => "object", "default" => settings}},
                "required" => [], "additionalProperties" => false}
      expect(described_class.new(schema).validate!({})).to eq("settings" => settings)
    end
  end

  it "fills in a declared default for an argument left out or sent as null" do
    schema = {"type" => "object", "properties" => {"limit" => {"type" => "integer", "default" => 25}}, "required" => [], "additionalProperties" => false}
    checker = described_class.new(schema)
    expect(checker.validate!({})).to eq("limit" => 25)
    expect(checker.validate!(limit: nil)).to eq("limit" => 25)
    expect(checker.validate!(limit: 5)).to eq("limit" => 5)
  end

  it "checks a declared default against the schema, as if the caller had sent it" do
    schema = {"type" => "object", "properties" => {"limit" => {"type" => "integer", "default" => "wrong"}}, "required" => [], "additionalProperties" => false}
    expect { described_class.new(schema).validate!({}) }
      .to raise_error(Saltbox::Actions::Error::ValidationFailed) { expect(it.errors.keys).to eq(["limit"]) }
  end

  it "lets a default satisfy a required argument" do
    schema = {"type" => "object", "properties" => {"limit" => {"type" => "integer", "default" => 25}}, "required" => ["limit"], "additionalProperties" => false}
    expect(described_class.new(schema).validate!({})).to eq("limit" => 25)
  end

  it "gives each call its own copy of a default, so changing it in one call never reaches the next" do
    schema = {"type" => "object", "properties" => {"memo" => {"type" => "string", "default" => "seed"}, "tags" => {"type" => "array", "default" => [["a"]]}},
              "required" => [], "additionalProperties" => false}
    checker = described_class.new(schema)
    first = checker.validate!({})
    first["memo"].replace("alice-private")
    first["tags"].first << "b"
    expect(checker.validate!({})).to eq("memo" => "seed", "tags" => [["a"]])
    expect(schema.dig("properties", "memo", "default")).to eq("seed")
  end
end
