module Api
  module V1
    # The catalogue and run endpoint. A test token names the account; a real
    # app resolves an OAuth bearer here.
    class ActionsController < ApplicationController
      include Saltbox::Actions::Controller

      ACCOUNTS = {
        "manager" => {id: 1, permissions: %w[events.view events.manage events.delete]},
        "reader" => {id: 2, permissions: %w[events.view]}
      }.freeze

      private

      def resolve_caller
        token = request.authorization.to_s.delete_prefix("Bearer ")
        account = ACCOUNTS[token] || raise(Saltbox::Actions::Error::Unauthorized)
        scopes = (request.headers["X-Scopes"] || "api:read api:write").split
        ApplicationAction::Caller.new(account: Account.new(**account), surface: "api", agent: "script", scopes:)
      end
    end
  end
end
