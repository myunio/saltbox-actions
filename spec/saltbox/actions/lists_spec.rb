# Saltbox::Actions::Lists: table, table_index and paginate, through the
# app's Configuration#list_adapter.
RSpec.describe Saltbox::Actions::Lists do
  # The app's table library, as the dummy app would write its adapter.
  let(:adapter) do
    Module.new do
      def self.filters(_table) = {"status" => {"type" => "string", "enum" => %w[draft published cancelled], "description" => "The event's status"},
                                  "starts" => {"type" => "object", "properties" => {"from" => {"type" => "string"}}, "additionalProperties" => false}}

      def self.search?(table) = table == :events

      def self.query(_table, user:, params:)
        events = Event.where(org_id: user.org_id).order(:id)
        events = events.where("title LIKE ?", "%#{params["search"]}%") if params["search"]
        events = events.where(status: params.dig("filter", "status")) if params.dig("filter", "status")
        events
      end

      def self.metadata(table, user:, params:) = {"table" => table.to_s, "params" => params}

      def self.paginate(collection, page:, page_size:) = [collection.offset((page - 1) * page_size).limit(page_size).to_a, {"page" => page, "page_size" => page_size}]
    end
  end
  let(:config) { Saltbox::Actions.config }
  let(:list) do
    Class.new(ApplicationAction) do
      def self.name = "Events::ListAction"
      table :events

      def perform
        records, table, pagination = table_index
        render json: {"titles" => records.map(&:title), "table" => table, "pagination" => pagination}, collection: records
      end
    end
  end
  let(:run) { ->(arguments) { Saltbox::Actions::Invocation.call(action: list, caller: as_screen(manager), arguments:).body } }

  around do |example|
    config.list_adapter = nil
    example.run
  ensure
    config.list_adapter = nil
  end

  before { config.list_adapter = adapter }

  it "declares paging, sort, search and one input per filter, with the filter's schema" do
    schema = list.input_schema.fetch("properties")
    expect(schema.keys).to contain_exactly("page", "page_size", "search", "sort", "status", "starts")
    expect(schema.fetch("status")).to include("type" => "string", "enum" => %w[draft published cancelled])
    expect(schema.fetch("page_size")).to include("default" => 25)
  end

  it "runs the table's query, its metadata and one page" do
    %w[AGM Picnic Party].each { Event.create!(org_id: 1, title: it) }
    Event.create!(org_id: 1, title: "Gala", status: "published")
    body = run.call(search: "P", page_size: 1, page: 2)
    expect(body).to eq("titles" => ["Party"], "table" => {"table" => "events", "params" => {"search" => "P"}},
      "pagination" => {"page" => 2, "page_size" => 1})
    expect(run.call(status: "published")["titles"]).to eq(["Gala"])
  end

  it "refuses a filter value outside its enum or schema" do
    expect { run.call(status: "lost") }.to have_field_errors(:status)
    expect { run.call(starts: {"until" => "2026-01-01"}) }.to have_field_errors(:starts)
  end

  it "pages a list with no table, and takes its default sizes from the configuration" do
    original = [config.page_size, config.max_page_size]
    config.page_size = 2
    config.max_page_size = 3
    paged = Class.new(ApplicationAction) do
      def self.name = "Events::ListAction"
      paginated

      def perform
        records = paginate(policy_scope(Event).order(:id))
        render json: {"titles" => records.map(&:title), "pagination" => @pagination}, collection: records
      end
    end
    %w[A B C].each { Event.create!(org_id: 1, title: it) }
    body = Saltbox::Actions::Invocation.call(action: paged, caller: as_screen(manager), arguments: {}).body
    expect(body).to eq("titles" => %w[A B], "pagination" => {"page" => 1, "page_size" => 2})
    expect { Saltbox::Actions::Invocation.call(action: paged, caller: as_screen(manager), arguments: {page_size: 4}) }.to have_field_errors(:page_size)
  ensure
    config.page_size, config.max_page_size = original
  end

  it "needs a list adapter to page" do
    config.list_adapter = nil
    expect { list }.to raise_error(ArgumentError, /config.list_adapter/)
  end
end
