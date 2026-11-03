# Saltbox::Actions.within: refresh_caller, around_invocation, check_caller.
RSpec.describe "Running as a caller" do
  let(:config) { Saltbox::Actions.config }

  def with_hooks(refresh: config.refresh_caller, around: config.around_invocation, check: config.check_caller)
    original = [config.refresh_caller, config.around_invocation, config.check_caller]
    config.refresh_caller(&refresh)
    config.around_invocation(&around)
    config.check_caller(&check)
    yield
  ensure
    config.refresh_caller(&original[0])
    config.around_invocation(&original[1])
    config.check_caller(&original[2])
  end

  it "refreshes the caller first, sets it up with the fresh one, then checks it inside the set-up" do
    seen = []
    with_hooks(refresh: ->(caller) { seen << [:refresh, caller.user.id] and caller.with(user: reader) },
      around: ->(caller, run) { seen << [:around, caller.user.id] and DummyCurrent.set(org: :set_up) { run.call(caller) } },
      check: ->(caller) { seen << [:check, caller.user.id, DummyCurrent.org] }) do
      result = Saltbox::Actions.within(as_screen(manager)) { |fresh| seen << [:block, fresh.user.id] and :done }
      expect(result).to eq(:done)
    end
    expect(seen).to eq([[:refresh, manager.id], [:around, reader.id], [:check, reader.id, :set_up], [:block, reader.id]])
  end

  it "runs every invocation with the refreshed caller, and lets a refresh or a check refuse it" do
    event = Event.create!(org_id: 1, title: "AGM")
    with_hooks(refresh: ->(caller) { caller.with(user: stranger) }) do
      expect { Saltbox::Actions::Invocation.call(action: "update_event", caller: as_screen(manager), arguments: {id: event.id.to_s, title: "X"}) }
        .to be_refused.with(:forbidden)
    end
    with_hooks(check: ->(caller) { raise Saltbox::Actions::Error::Forbidden if caller.surface == "assistant" }) do
      expect { Saltbox::Actions::Invocation.call(action: "show_event", caller: as_assistant(manager), arguments: {id: event.id.to_s}) }
        .to be_refused.with(:forbidden)
      expect { Saltbox::Actions::AgentTools.call("find_action", {query: "event"}, caller: as_assistant(manager)) }
        .to raise_error(Saltbox::Actions::Error::Forbidden)
    end
    expect(event.reload.title).to eq("AGM")
  end
end
