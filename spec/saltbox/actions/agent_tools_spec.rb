RSpec.describe Saltbox::Actions::AgentTools do
  let(:event) { Event.create!(org_id: 1, title: "Annual general meeting") }

  it "offers featured actions as tools of their own, then find_action and one run tool per kind the caller may run" do
    expect(Saltbox::Actions::Registry.catalog(as_mcp(manager)).select { it["featured"] }.map { it["name"] }).to eq(%w[show_event whoami])
    expect(Saltbox::Actions::Registry.catalog(as_mcp(manager)).flat_map(&:keys)).not_to include("mcp_core")
    expect(described_class.tools(as_mcp(manager)).map(&:name)).to eq(%w[show_event whoami find_action run_read_action run_change_action run_destructive_action])
    expect(described_class.tools(as_read_only(manager)).map(&:name)).to eq(%w[show_event whoami find_action run_read_action])
    expect(described_class.tools(as_assistant(manager)).map(&:name)).not_to include("run_destructive_action")
  end

  it "names the app in its tool titles and gives MCP behaviour hints" do
    find, read = described_class.tools(as_mcp(manager)).values_at(2, 3)
    expect(find.title).to eq("Find something to do in Dummy")
    expect(read.title).to eq("Look something up in Dummy")
    expect(read.annotations).to eq(read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false)
  end

  it "finds an action from everyday words, with its arguments and the run tool to use" do
    found = described_class.call("find_action", {"query" => "cancel the meeting"}, caller: as_mcp(manager))
    expect(found[:actions].first).to include(name: "cancel_event", run_with: "run_change_action", confirm_first: true)
  end

  it "tells the agent when only a person may run what it found" do
    found = described_class.call("find_action", {"query" => "private notes"}, caller: as_mcp(User.new(id: 9, permissions: %w[events.view events.notes])))
    expect(found[:actions].first).to include(name: "show_event_notes", run_with: nil, message: "Only a person can do this, in Dummy")
  end

  describe "find_action with no query" do
    def listed(user, caller: as_mcp(user), **paging) = described_class.call("find_action", paging, caller:)[:actions]

    it "lists every action the caller can run, by area then name, without descriptions or arguments" do
      expect(listed(manager).pluck(:name)).to eq(%w[cancel_event create_event delete_event list_events postpone_event show_event update_event count_events whoami])
      expect(listed(manager)).to all(satisfy { |entry| !entry.key?(:description) && !entry.key?(:arguments) })
      expect(listed(manager)).to include({name: "delete_event", title: "Delete event", kind: "destructive", area: "events",
        run_with: "run_destructive_action", confirm_first: true}, {name: "whoami", title: "Whoami", kind: "read", run_with: "run_read_action", confirm_first: false})
    end

    it "lists only what the caller can run from its surface, never what only a person may run" do
      expect(listed(reader).pluck(:name)).to eq(%w[list_events show_event whoami])
      expect(listed(manager, caller: as_read_only(manager)).pluck(:kind).uniq).to eq(%w[read])
      expect(listed(User.new(id: 9, permissions: %w[events.view events.notes])).pluck(:name)).not_to include("show_event_notes")
      expect(listed(manager, caller: as_assistant(manager)).pluck(:name)).not_to include("cancel_event", "delete_event")
      expect(listed(manager, caller: as_webmcp(manager)).pluck(:name)).not_to include("delete_event")
      expect(listed(manager, caller: as_assistant(manager))).to all(satisfy { |entry| entry[:run_with] && !entry.key?(:message) })
    end

    it "lists a page at a time, and following the hint's next page reaches every action once" do
      first = described_class.call("find_action", {"page_size" => 3}, caller: as_mcp(manager))
      expect(first[:actions].pluck(:name)).to eq(%w[cancel_event create_event delete_event])
      expect(first[:meta]).to eq(page: 1, page_size: 3, total: 9, next_page: 2)
      expect(first[:hint]).to include("Call find_action with page: 2, page_size: 3 for more.")

      pages = [first]
      while (next_args = pages.last[:hint][/page: (\d+), page_size: (\d+)/] && {"page" => $1.to_i, "page_size" => $2.to_i})
        pages << described_class.call("find_action", next_args, caller: as_mcp(manager))
      end
      expect(pages.size).to eq(3)
      expect(pages.flat_map { |page| page[:actions].pluck(:name) }).to eq(listed(manager).pluck(:name))
      expect(pages.last[:meta]).to include(next_page: nil)
      expect(described_class.call("find_action", {}, caller: as_mcp(manager))[:meta]).to include(page_size: 50)
    end

    it "refuses a page size over the most, and paging with a query" do
      expect { described_class.call("find_action", {"page_size" => 101}, caller: as_mcp(manager)) }.to have_field_errors(:page_size)
      expect { described_class.call("find_action", {"query" => "events", "page" => 2}, caller: as_mcp(manager)) }.to have_field_errors(:page)
    end

    it "gives a plain list, by name, in an app with no areas" do
      allow(Saltbox::Actions.config).to receive(:area_for).and_return(->(_model) {})
      expect(listed(manager).pluck(:name)).to eq(%w[cancel_event count_events create_event delete_event list_events postpone_event show_event update_event whoami])
      expect(listed(manager)).to all(satisfy { |entry| !entry.key?(:area) })
    end

    it "puts the areas in config.area_order first" do
      allow(Reports::CountEventsAction).to receive(:area).and_return("reports")
      expect(listed(manager).pluck(:area).uniq).to eq(["events", "reports", nil])
      with_settings(area_order: %w[reports]) { expect(listed(manager).pluck(:area).uniq).to eq(["reports", "events", nil]) }
    end
  end

  it "names the caller's areas when nothing matches, and only when actions have areas" do
    hint = described_class.call("find_action", {"query" => "payroll"}, caller: as_mcp(manager))[:hint]
    expect(hint).to eq("Nothing matched. Try other words, or Dummy may not do this yet. You can reach events. Call find_action with no query to list everything you can run.")
    allow(Saltbox::Actions.config).to receive(:area_for).and_return(->(_model) {})
    hint = described_class.call("find_action", {"query" => "payroll"}, caller: as_mcp(manager))[:hint]
    expect(hint).to eq("Nothing matched. Try other words, or Dummy may not do this yet. Call find_action with no query to list everything you can run.")
  end

  it "asks first for a change only when find_action marks it confirm_first, and always before removing" do
    change, destructive = described_class.tools(as_mcp(manager)).values_at(4, 5).map(&:description)
    expect(change).to include("When find_action marks it confirm_first, say what will change and get a yes first; otherwise say what you are changing and go ahead.")
    expect(destructive).to include("get a yes first")
  end

  it "lists only what a connection's access reaches, in its tools, find_action and the catalog" do
    reads_only = Struct.new(:kind) { def allows?(action) = action.kind == kind }.new(:read)
    connection = Saltbox::Actions::Caller.new(user: manager, surface: "mcp", agent_name: "Claude", access: reads_only)
    expect(described_class.tools(connection).map(&:name)).to eq(%w[show_event whoami find_action run_read_action])
    expect(described_class.call("find_action", {"query" => "cancel the meeting"}, caller: connection)[:actions]).to be_empty
    listed = Saltbox::Actions::Registry.catalog(connection).pluck("name")
    expect(listed).to include("list_events")
    expect(listed).not_to include("cancel_event", "delete_event")
  end

  it "shows an action with no model and no declared permission to no one, in its tools, find_action and the catalog" do
    unguarded = Class.new(ApplicationAction) do
      def self.name = "TallyEventsAction"
      kind :read
      featured
      description "Use this when the person asks how many events there are."
      def perform = render(json: {count: policy_scope(authorize(Event)).count})
    end
    allow(Saltbox::Actions::Registry).to receive(:actions).and_wrap_original { |original| [*original.call, unguarded] }
    expect(unguarded).not_to be_listed_for(as_mcp(stranger))
    expect(described_class.tools(as_mcp(stranger)).map(&:name)).not_to include("tally_events")
    expect(described_class.call("find_action", {"query" => "how many events"}, caller: as_mcp(stranger))[:actions].pluck(:name)).not_to include("tally_events")
    expect(Saltbox::Actions::Registry.catalog(as_mcp(stranger)).pluck("name")).not_to include("tally_events")
  end

  it "runs direct and generic tools through Invocation, refusing the wrong kind" do
    expect(described_class.call("show_event", {"id" => event.id.to_s}, caller: as_mcp(manager)).dig("data", "event", "title")).to eq(event.title)
    expect(described_class.call("run_read_action", {"name" => "list_events"}, caller: as_mcp(manager)).dig("data", "events").size).to eq(1)
    expect { described_class.call("run_read_action", {"name" => "delete_event", "arguments" => {"id" => event.id.to_s}}, caller: as_mcp(manager)) }
      .to be_refused.with(:validation_failed)
    expect { described_class.call("update_event", {}, caller: as_mcp(manager)) }.to be_refused.with(:unknown_action)
  end

  it "checks the run tool's own wrapper" do
    expect { described_class.call("run_read_action", {"arguments" => {}, "extra" => 1}, caller: as_mcp(manager)) }.to have_field_errors(:name, :extra)
  end
end
