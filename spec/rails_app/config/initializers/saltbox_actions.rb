# The dummy app's choices, as an app writes them. ANNOUNCED keeps each
# change's records, so specs can see what on_changes received.
module Dummy
  ANNOUNCED = []
end

# The suite runs once for each way an app authorizes (see the Rakefile):
# with Pundit, ActionPolicy, or no adapter at all.
authorization = ENV.fetch("SALTBOX_ACTIONS_AUTHORIZATION", "pundit")
Saltbox::Actions.configure do |config|
  config.adapters = [*((authorization == "none") ? [] : [authorization.to_sym]),
    :controller, :mcp, :ruby_llm_tool, :invocation_job, :paper_trail, :approvals]
  config.app_name = "Dummy"
  config.instructions = "Dummy keeps events. Call find_action for anything not listed."
  config.max_array_items = 50
  config.require_area = true
  config.area_for { |model| {"Event" => "events", "Billing::Invoice" => "billing"}[model.name] }
  config.permissions_held do |caller|
    next [] if caller.system? || caller.user.permissions == :all
    caller.user.permissions
  end
  config.schema_user { |run| run.call(User.new(id: 0, permissions: :all)) }
  config.around_perform do |invocation, run|
    Saltbox::Actions::Adapters::Audit::PaperTrail.request(invocation, agent: invocation.caller.agent_name,
      surface: invocation.caller.surface, invocation_id: invocation.invocation_id) { run.call }
  end
  config.on_changes { |changes, invocation| Dummy::ANNOUNCED << {action: invocation.action.action_name, changes:} }
end
