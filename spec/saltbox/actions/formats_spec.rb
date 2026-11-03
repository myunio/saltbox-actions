# The error and result bodies an app that predates the gem keeps
# (Configuration#error_format and #result_format).
RSpec.describe "Error and result formats" do
  let(:invalid) { Saltbox::Actions::Error::ValidationFailed.new("Title can't be blank", errors: {"title" => ["can't be blank"]}, details: {hint: "name it"}) }

  it "sends code and errors by default, and type with the fields in details for :type" do
    expect(invalid.as_json).to eq("error" => {"code" => "validation_failed", "message" => "Title can't be blank",
                                              "errors" => {"title" => ["can't be blank"]}, "details" => {hint: "name it"}})
    with_settings(error_format: :type) do
      expect(invalid.as_json).to eq("error" => {"type" => "validation_error", "message" => "Title can't be blank",
                                                "details" => {"hint" => "name it", "fields" => ["title"]}})
      expect(Saltbox::Actions::Error::NotFound.new.as_json).to eq("error" => {"type" => "not_found", "message" => "Not found."})
    end
  end

  it "builds a validation refusal from a result's messages, or from errors by field" do
    from_result = Saltbox::Actions::Error::ValidationFailed.from_result(Struct.new(:errors).new(["Too late", "Full"]))
    expect([from_result.code, from_result.message, from_result.errors]).to eq(["validation_failed", "Too late; Full", nil])
    errors = ActiveModel::Errors.new(Event.new).tap { it.add(:title, :blank) }
    built = Saltbox::Actions::Error::ValidationFailed.for(errors)
    expect([built.code, built.message, built.errors]).to eq(["validation_failed", "Title can't be blank", {"title" => ["can't be blank"]}])
  end

  it "sends the rendered body by default, and data with meta for :envelope" do
    result = Saltbox::Actions::Result.new(status: 200, body: {count: 1}, meta: {page: 1})
    expect(result.as_json).to eq(count: 1)
    with_settings(result_format: :envelope) do
      expect(result.as_json).to eq("data" => {"count" => 1}, "meta" => {"page" => 1})
      expect(Saltbox::Actions::Result.new(status: 200, body: [], meta: nil).as_json).to eq("data" => [])
    end
  end

  it "answers the API in the envelope", type: :request do
    with_settings(result_format: :envelope, error_format: :type) do
      headers = {"Authorization" => "Bearer manager", "CONTENT_TYPE" => "application/json"}
      post "/api/v1/actions/count_events", params: {arguments: {}}.to_json, headers: headers
      expect(response.parsed_body).to eq("data" => {"count" => 0}, "meta" => {"page" => 1})
      post "/api/v1/actions/count_events", params: {arguments: {page: 0}}.to_json, headers: headers
      expect(response.parsed_body.dig("error", "type")).to eq("validation_error")
      expect(response.parsed_body.dig("error", "details", "fields")).to eq(["page"])
    end
  end
end
