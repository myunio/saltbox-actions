RSpec.describe "The actions API", type: :request do
  let(:event) { Event.create!(org_id: 1, title: "AGM") }
  let(:headers) { {"Authorization" => "Bearer manager", "CONTENT_TYPE" => "application/json"} }

  it "lists the actions this caller may use, with an ETag" do
    get "/api/v1/actions", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("meta", "version")).to eq(Saltbox::Actions::Registry.version)
    expect(response.parsed_body["data"].pluck("name")).to include("update_event")
    get "/api/v1/actions", headers: headers.merge("If-None-Match" => response.headers["ETag"])
    expect(response).to have_http_status(:not_modified)
  end

  it "shows one definition and answers an unknown name" do
    get "/api/v1/actions/update_event", headers: headers
    expect(response.parsed_body.dig("data", "kind")).to eq("change")
    get "/api/v1/actions/fly_event", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.dig("error", "code")).to eq("unknown_action")
  end

  it "runs an action with its arguments and answers with its body and status" do
    post "/api/v1/actions/create_event", params: {arguments: {title: "Picnic"}}.to_json, headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("data", "event", "title")).to eq("Picnic")
  end

  it "refuses what the token may not do, a body that is not an object, and an unknown token" do
    post "/api/v1/actions/update_event", params: {arguments: {id: event.id.to_s}}.to_json, headers: headers.merge("X-Scopes" => "api:read")
    expect(response.parsed_body.dig("error", "code")).to eq("insufficient_scope")
    post "/api/v1/actions/create_event", params: {title: "Loose"}.to_json, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    post "/api/v1/actions/create_event", params: "{", headers: headers
    expect(response.parsed_body.dig("error", "message")).to eq("The request body is not valid JSON")
    get "/api/v1/actions", headers: {"Authorization" => "Bearer nobody"}
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to eq("Bearer")
  end

  it "answers a delete with no content" do
    post "/api/v1/actions/delete_event", params: {arguments: {id: event.id.to_s}}.to_json, headers: headers
    expect(response).to have_http_status(:no_content)
  end

  it "refuses a :confirm action the app has not approved, with enforce_confirm on" do
    with_settings(enforce_confirm: true) do
      post "/api/v1/actions/cancel_event", params: {arguments: {id: event.id.to_s}}.to_json, headers: headers
    end
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq("error" => {"code" => "confirmation_required",
                                                   "message" => "The person must approve this in Dummy before it runs.", "details" => {"action" => "cancel_event"}})
    expect(event.reload.status).to eq("draft")
  end
end
