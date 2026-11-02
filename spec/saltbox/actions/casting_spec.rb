RSpec.describe Saltbox::Actions::Casting do
  let(:event) { Event.create!(org_id: 1, title: "AGM", capacity: 40, price: 10, starts_on: Date.new(2026, 11, 2)) }
  let(:update) { ->(arguments, caller = as_screen(manager)) { Saltbox::Actions::Invocation.call(name: "update_event", caller:, arguments: {id: event.id}.merge(arguments)) } }

  it "takes what an HTML form sends from a screen, as Active Record would" do
    update.call({"capacity" => "12", "price" => "12.30", "featured" => "on", "doors_open_at" => "2026-11-02T18:30", "status" => "published"})
    expect(event.reload).to have_attributes(capacity: 12, price: BigDecimal("12.30"), featured: true, status: "published",
      doors_open_at: Time.zone.parse("2026-11-02 18:30"))
    update.call({"featured" => "0"})
    expect(event.reload.featured).to be(false)
  end

  it "clears a number or a date sent as an empty field, and keeps an empty string as a string" do
    update.call({"capacity" => "", "price" => "", "starts_on" => "", "doors_open_at" => ""})
    expect(event.reload).to have_attributes(capacity: nil, price: nil, starts_on: nil, doors_open_at: nil)
    expect(Saltbox::Actions::Arguments.for(Events::CreateAction).validate!(title: "")).to eq("title" => "")
  end

  it "treats an empty field that cannot be null as left out" do
    update.call({"featured" => "", "status" => ""})
    expect(event.reload).to have_attributes(featured: false, status: "draft")
  end

  it "takes an integer id and an integer reference, from any surface" do
    parent = Event.create!(org_id: 1, title: "Conference")
    update.call({parent: parent.id}, as_mcp(manager))
    expect(event.reload.parent).to eq(parent)
    update.call({"parent" => ""})
    expect(event.reload.parent).to be_nil
  end

  it "takes a decimal as a number or a string, keeping every digit of the string" do
    update.call({price: 9.5}, as_mcp(manager))
    expect(event.reload.price).to eq(BigDecimal("9.5"))
    update.call({price: "123456.78"}, as_mcp(manager))
    expect(event.reload.price).to eq(BigDecimal("123456.78"))
  end

  it "refuses a value that is not of its type, naming each field, rather than casting it to 0 or true" do
    expect { update.call({"capacity" => "lots", "price" => "12,30", "featured" => "maybe", "doors_open_at" => "soon"}) }
      .to have_field_errors(:capacity, :price, :featured, :doors_open_at)
    expect(event.reload).to have_attributes(capacity: 40, price: BigDecimal(10), featured: false)
  end

  it "refuses a local date-time that is not on the calendar, rather than rolling it over" do
    expect { update.call({"doors_open_at" => "2026-02-30T12:30"}) }.to have_field_errors(:doors_open_at)
    expect { update.call({"doors_open_at" => "2026-11-02T24:30"}) }.to have_field_errors(:doors_open_at)
  end

  it "keeps a local date-time's fraction of a second, as Active Record does" do
    update.call({"doors_open_at" => "2026-11-02T18:30:12.123456"})
    expect(event.reload.doors_open_at).to eq(Time.zone.parse("2026-11-02 18:30:12.123456"))
  end

  it "refuses an integer its column cannot store, from a form or as a JSON number" do
    expect { update.call({"capacity" => "9223372036854775808"}) }.to have_field_errors(:capacity)
    expect { update.call({capacity: 2**63}, as_mcp(manager)) }.to have_field_errors(:capacity)
    expect(event.reload.capacity).to eq(40)
  end

  it "refuses a float that is not finite, which JSON cannot carry" do
    schema = {"type" => "object", "properties" => {"ratio" => {"type" => "number"}}, "required" => [], "additionalProperties" => false}
    checker = Saltbox::Actions::Arguments.new(schema, types: {"ratio" => ActiveModel::Type::Float.new})
    expect(checker.validate!("ratio" => "1.5")).to eq("ratio" => 1.5)
    %w[1e999 NaN Infinity].each do |value|
      expect { checker.validate!("ratio" => value) }.to raise_error(Saltbox::Actions::Error::Invalid) { expect(it.errors.keys).to eq(["ratio"]) }
    end
    expect { checker.validate!("ratio" => Float::INFINITY) }.to raise_error(Saltbox::Actions::Error::Invalid) { expect(it.errors.keys).to eq(["ratio"]) }
  end

  it "casts attributes from a form, including the items of a list, and drops a form's blank list item" do
    action = Class.new(ApplicationAction) do
      def self.name = "Events::ImportAction"
      kind :change
      attribute :rows, :array, of: {capacity: :integer, paid: :boolean, on: :date}
      attribute :ids, :array, of: :integer
      attribute :page, :integer
      attribute :amount, :decimal
    end
    input = {"rows" => [{"capacity" => "3", "paid" => "1", "on" => "2026-11-02"}], "ids" => ["", "4", "5"], "page" => "2", "amount" => "1.50"}
    checked = Saltbox::Actions::Arguments.for(action).validate!(input)
    expect(checked).to eq("rows" => [{"capacity" => 3, "paid" => true, "on" => "2026-11-02"}], "ids" => [4, 5], "page" => 2, "amount" => "1.50")
    built = action.new(actor: as_screen(manager), params: Saltbox::Actions::Params.new(checked, action:))
    expect([built.rows, built.ids, built.page, built.amount])
      .to eq([[{"capacity" => 3, "paid" => true, "on" => Date.new(2026, 11, 2)}], [4, 5], 2, BigDecimal("1.50")])
    expect { Saltbox::Actions::Arguments.for(action).validate!("page" => "two", "amount" => "1.5.0") }
      .to raise_error(Saltbox::Actions::Error::Invalid) { expect(it.errors.keys).to contain_exactly("page", "amount") }
  end
end
