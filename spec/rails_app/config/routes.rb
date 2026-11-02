Rails.application.routes.draw do
  default_url_options host: "dummy.test", protocol: "https"

  namespace :api do
    namespace :v1 do
      get "actions", to: "actions#index"
      get "actions/:name", to: "actions#show"
      post "actions/:name", to: "actions#run"
    end
  end
end
