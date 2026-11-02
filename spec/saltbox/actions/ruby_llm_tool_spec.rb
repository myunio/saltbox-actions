require "saltbox/actions/ruby_llm"

RSpec.describe Saltbox::Actions::RubyLLMTool do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }

  it "gives the chat the tools its person may run, each with the front door's schema" do
    tools = described_class.for(as_assistant(manager))
    expect(tools.map(&:name)).to eq(%w[show_event whoami find_action run_read_action run_change_action])
    expect(tools.first.parameters_schema).to eq(Event::ShowAction.input_schema)
  end

  it "runs a tool as the person, returning the body or the refusal" do
    run_change = described_class.for(as_assistant(manager)).find { it.name == "run_change_action" }
    expect(run_change.call(name: "update_event", arguments: {id: event.id.to_s, title: "Renamed"}).dig("data", "event", "title")).to eq("Renamed")
    expect(run_change.call(name: "cancel_event", arguments: {id: event.id.to_s}).dig("error", "code")).to eq("human_required")
  end
end
