# An app whose action names, CLI commands and permissions were public before
# it used the gem declares them (Reports::CountEventsAction).
RSpec.describe "Declared names" do
  let(:action) { Reports::CountEventsAction }

  def named(class_name, &block)
    Class.new(ApplicationAction) do
      define_singleton_method(:name) { class_name }
      class_eval(&block)
    end
  end

  it "takes the declared name, title, description and CLI command in place of the class name's" do
    expect(action).to have_attributes(action_name: "count_events", title: "Count events", kind: :read, model: nil,
      cli_command: %w[events count], cli_args: %w[status])
    expect(action.summary.names).to eq(%w[count])
    expect(action.description).to start_with("Use this when the person asks how many events")
    expect(action.definition).to include("permissions" => ["events.view"], "permissions_any_of" => [%w[events.manage events.delete]],
      "cli" => {"command" => %w[events count], "aliases" => [%w[events tally]], "args" => %w[status]}, "summary" => %w[count])
  end

  it "describes each attribute in its declaration, after what its validations give" do
    expect(action.input_schema.fetch("properties")).to eq(
      "status" => {"type" => "string", "enum" => %w[draft published cancelled], "description" => "Only events with this status"},
      "page" => {"type" => "integer", "minimum" => 1, "description" => "Page number, from 1"}
    )
    unknown_cli_args = lambda do
      named("Reports::BadAction") do
        action_name "bad"
        cli "reports bad", args: %w[nope]
      end
    end
    expect(&unknown_cli_args).to raise_error(ArgumentError, /cli args nope are not attributes/)
  end

  it "names the missing policy rule when a named action with a model runs, as rails actions:check does" do
    unruled = named("Reports::PeekAction") do
      action_name "peek_events"
      kind :read
      model Event
      def perform = render(json: {})
    end
    expect { Saltbox::Actions::Invocation.call(name: unruled, caller: as_screen(manager), arguments: {}) }
      .to raise_error(ArgumentError, "Reports::PeekAction: Event is its model: name the policy rule, policy_rule :show? or another")
  end

  it "holds a named action to its own boot checks: a declared kind, and its model's policy if it names one" do
    problems = ->(action) { Saltbox::Actions::Registry.problems(action) }
    bare = named("Reports::BareAction") { action_name "bare" }
    expect(problems.call(bare)).to eq(["declare kind :read, :change or :destructive"])

    read = named("Reports::ReadAction") do
      action_name "read_it"
      kind :read
    end
    expect(problems.call(read)).to be_empty
    expect(read.connections).to eq(:allowed)

    tally = named("Reports::TallyAction") do
      action_name "tally"
      kind :read
      connections :allowed
      model Event
    end
    expect(problems.call(tally)).to eq(["Event is its model: name the policy rule, policy_rule :show? or another"])
    tally.policy_rule :tally?
    expect(problems.call(tally)).to eq(["EventPolicy#tally? is missing: add it, or name another with policy_rule"])
  end

  it "needs at least one requirement, and two keys or more for any_of" do
    expect { named("Reports::BadAction") { permission } }.to raise_error(ArgumentError, "permission needs a key or :everyone")
    expect { named("Reports::BadAction") { permission any_of("events.view") } }.to raise_error(ArgumentError, "any_of needs two keys or more")
    expect(named("Reports::OpenAction") { permission :everyone }.permissions_met?([])).to be(true)
  end

  it "decides only the actions list when permissions are not enforced" do
    with_settings(enforce_permissions: false) do
      expect(action).not_to be_listed_for(as_api(reader))
      expect(run({}, as: as_api(reader), action:).body).to eq("count" => 0)
    end
  end

  it "asks a declared permission in place of the policy's role question" do
    open_to_all = named("Reports::OpenAction") do
      action_name "open_report"
      kind :read
      connections :allowed
      permission :everyone
    end
    allow(open_to_all).to receive(:permitted?).and_return(false)
    expect(open_to_all.permitted_for?(as_api(stranger))).to be(true)
  end
end
