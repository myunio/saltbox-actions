module Api
  module V1
    # The catalog and run endpoint. A test token names the user; a real
    # app resolves an OAuth bearer here.
    class ActionsController < ApplicationController
      include Saltbox::Actions::Controller

      USERS = {
        "manager" => {id: 1, permissions: %w[events.view events.manage events.delete]},
        "reader" => {id: 2, permissions: %w[events.view]}
      }.freeze

      private

      def current_caller
        token = request.authorization.to_s.delete_prefix("Bearer ")
        user = USERS[token] || raise(Saltbox::Actions::Error::Unauthorized)
        scopes = (request.headers["X-Scopes"] || "api:read api:write").split
        ApplicationAction::Caller.new(user: User.new(**user), surface: "api", agent_name: "script", scopes:)
      end
    end
  end
end
