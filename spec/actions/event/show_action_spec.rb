RSpec.describe Event::ShowAction do
  let(:permitted_account) { reader }
  let(:unpermitted_account) { stranger }
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:arguments) { {id: event.id.to_s} }

  before do
    described_class.returns(type: "object", required: %w[data], properties: {
      data: {type: "object", required: %w[event], properties: {event: {type: "object", required: %w[id title]}}}
    })
  end

  after { described_class.instance_variable_set(:@output_schema, nil) }

  it_behaves_like "refuses callers the action does not allow"
  it_behaves_like "renders its declared output schema"

  it_behaves_like "hides records the caller cannot see" do
    let(:hidden_arguments) { {id: Event.create!(org_id: 2, title: "Elsewhere").id.to_s} }
  end

  it "names a body that does not match its output schema" do
    expect(match_output_schema.matches?(Saltbox::Actions::Result.new(status: 200, body: {"data" => {}}))).to be(false)
  end
end
