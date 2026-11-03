require "saltbox/actions/mcp"
require "saltbox/actions/ruby_llm"

# Every JSON value an action renders reaches each surface as that value,
# marked as record data; only a response with no body (head) is "Done.".
RSpec.describe "Response bodies on every surface" do
  def answering(body)
    Class.new(ApplicationAction) do
      define_singleton_method(:name) { "Reports::AnswerAction" }
      permission :everyone
      action_name "answer"
      kind :read
      agents :allowed
      define_method(:perform) do
        skip_authorization
        skip_policy_scope
        body.equal?(:head) ? head(:no_content) : render(json: body)
      end
    end
  end

  def serving(body)
    allow(Saltbox::Actions::Registry).to receive(:fetch).and_call_original
    allow(Saltbox::Actions::Registry).to receive(:fetch).with("answer").and_return(answering(body))
  end

  def mcp_text(body)
    serving(body)
    Saltbox::Actions::MCP.invoke("run_read_action", {"name" => "answer"}, as_mcp(manager)).to_h.dig(:content, 0, :text)
  end

  def assistant_answer(body)
    serving(body)
    tool = Saltbox::Actions::RubyLLMTool.for(as_assistant(manager)).find { it.name == "run_read_action" }
    tool.call(name: "answer")
  end

  {false => "false", nil => "null", {"ok" => true} => '{"ok":true}'}.each do |body, json|
    it "sends #{json} as #{json}" do
      expect(mcp_text(body)).to eq("<record-data>\n#{json}\n</record-data>")
      expect(assistant_answer(body)).to eq("<record-data>\n#{json}\n</record-data>")
    end
  end

  {false => '{"data":false}', nil => '{"data":null}', {"ok" => true} => '{"data":{"ok":true}}'}.each do |body, json|
    it "sends #{body.inspect} as #{json} in the envelope format" do
      with_settings(result_format: :envelope) do
        expect(mcp_text(body)).to eq("<record-data>\n#{json}\n</record-data>")
        expect(assistant_answer(body)).to eq("<record-data>\n#{json}\n</record-data>")
      end
    end
  end

  it "says Done. for a response with no body" do
    expect(mcp_text(:head)).to eq("Done.")
    expect(assistant_answer(:head)).to eq("Done.")
    with_settings(result_format: :envelope) { expect(mcp_text(:head)).to eq("Done.") }
  end
end
