class WhoamiAction < ApplicationAction
  kind :read
  featured

  def perform
    skip_authorization
    skip_policy_scope
    render json: {data: {user_id: current_user.id, surface: current_caller.surface, agent: current_caller.agent_name}}
  end
end
