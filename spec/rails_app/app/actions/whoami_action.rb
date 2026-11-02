class WhoamiAction < ApplicationAction
  kind :read
  connections :allowed
  mcp_core

  def perform
    skip_authorization
    skip_policy_scope
    render json: {data: {account_id: account.id, surface: actor.surface, agent: actor.agent}}
  end
end
