RSpec.describe Saltbox::Actions::FrontDoor do
  let(:event) { Event.create!(org_id: 1, title: "Annual general meeting") }

  it "offers mcp_core actions as tools of their own, then find_action and one run tool per kind the caller may run" do
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
    found = described_class.call("find_action", {"query" => "private notes"}, caller: as_mcp(Account.new(id: 9, permissions: %w[events.view events.notes])))
    expect(found[:actions].first).to include(name: "show_event_notes", run_with: nil, message: "Only a person can do this, in Dummy")
  end

  describe "find_action with no query" do
    def listed(account) = described_class.call("find_action", {}, caller: as_mcp(account))[:actions]

    it "lists every action the caller may see, by area then name, without descriptions or arguments" do
      expect(listed(manager).pluck(:name)).to eq(%w[cancel_event create_event delete_event list_events show_event update_event count_events whoami])
      expect(listed(manager)).to all(satisfy { |entry| !entry.key?(:description) && !entry.key?(:arguments) })
      expect(listed(manager)).to include({name: "delete_event", title: "Delete event", kind: "destructive", area: "events",
        run_with: "run_destructive_action", confirm_first: true}, {name: "whoami", title: "Whoami", kind: "read", run_with: "run_read_action", confirm_first: false})
    end

    it "lists only what the caller's permissions and access reach, marking what only a person may run" do
      expect(listed(reader).pluck(:name)).to eq(%w[list_events show_event whoami])
      expect(described_class.call("find_action", {}, caller: as_read_only(manager))[:actions].pluck(:kind).uniq).to eq(%w[read])
      notes = listed(Account.new(id: 9, permissions: %w[events.view events.notes])).find { |entry| entry[:name] == "show_event_notes" }
      expect(notes).to include(run_with: nil, message: "Only a person can do this, in Dummy")
    end

    it "gives a plain list, by name, in an app with no areas" do
      allow(Saltbox::Actions.config).to receive(:area_for).and_return(->(_model) {})
      expect(listed(manager).pluck(:name)).to eq(%w[cancel_event count_events create_event delete_event list_events show_event update_event whoami])
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
    expect(hint).to eq("Nothing matched. Try other words, or Dummy may not do this yet. You can reach events. Call find_action with no query to list everything you can do.")
    allow(Saltbox::Actions.config).to receive(:area_for).and_return(->(_model) {})
    hint = described_class.call("find_action", {"query" => "payroll"}, caller: as_mcp(manager))[:hint]
    expect(hint).to eq("Nothing matched. Try other words, or Dummy may not do this yet. Call find_action with no query to list everything you can do.")
  end

  it "asks first for a change only when find_action marks it confirm_first, and always before removing" do
    change, destructive = described_class.tools(as_mcp(manager)).values_at(4, 5).map(&:description)
    expect(change).to include("When find_action marks it confirm_first, say what will change and get a yes first; otherwise say what you are changing and go ahead.")
    expect(destructive).to include("get a yes first")
  end

  it "lists only what a connection's access reaches, in its tools, find_action and the catalogue" do
    reads_only = Struct.new(:kind) { def allows?(action) = action.kind == kind }.new(:read)
    connection = Saltbox::Actions::Caller.new(account: manager, surface: "mcp", agent: "Claude", access: reads_only)
    expect(described_class.tools(connection).map(&:name)).to eq(%w[show_event whoami find_action run_read_action])
    expect(described_class.call("find_action", {"query" => "cancel the meeting"}, caller: connection)[:actions]).to be_empty
    listed = Saltbox::Actions::Registry.catalogue(connection).pluck("name")
    expect(listed).to include("list_events")
    expect(listed).not_to include("cancel_event", "delete_event")
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
