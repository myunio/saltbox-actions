RSpec.describe Saltbox::Actions::Rendering do
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
        render json: body
      end
    end
  end

  def run_answer(body) = Saltbox::Actions::Invocation.call(action: answering(body), caller: as_screen(manager))

  it "renders any JSON value given as json:, false and null included" do
    expect(run_answer(false)).to have_attributes(status: 200, body: false, empty?: false)
    expect(run_answer(nil)).to have_attributes(status: 200, body: nil, empty?: false)
    expect(run_answer(0).body).to eq(0)
  end

  it "answers the API with any JSON value as the body: false, null, a string, a number or an object", type: :request do
    headers = {"Authorization" => "Bearer manager", "CONTENT_TYPE" => "application/json"}
    allow(Saltbox::Actions::Registry).to receive(:fetch).and_call_original
    [false, nil, "hello", "true", 7, {"ok" => true}].each do |body|
      allow(Saltbox::Actions::Registry).to receive(:fetch).with("answer").and_return(answering(body))
      post "/api/v1/actions/answer", params: {arguments: {}}.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(body.to_json)
    end
  end
end
