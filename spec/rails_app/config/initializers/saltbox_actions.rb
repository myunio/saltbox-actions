# The dummy app's settings, as an app writes them: values only.
#
# The suite runs once for each way an app authorizes (see the Rakefile):
# with Pundit, ActionPolicy, or no adapter at all.
authorization = ENV.fetch("SALTBOX_ACTIONS_AUTHORIZATION", "pundit")
Saltbox::Actions.configure do |config|
  config.adapters = [*((authorization == "none") ? [] : [authorization.to_sym]),
    :acts_as_tenant, :controller, :mcp, :ruby_llm_tool, :invocation_job, :paper_trail, :approvals]
  config.app_name = "Dummy"
  config.instructions = "Dummy keeps events. Call find_action for anything not listed."
  config.max_array_items = 50
  config.require_area = true
  config.areas = {"events" => {models: %w[Event]}, "billing" => {models: %w[Billing::Invoice]}}
  # Approvals are kept per org, the tenant :acts_as_tenant sets.
  config.approvals = {user: "User", tenant: "Org"}
end

# What each change changed, as an app hears of it: ANNOUNCED keeps each
# change's records, so specs can see what the notification carried.
module Dummy
  ANNOUNCED = []
end
ActiveSupport::Notifications.subscribe("changes.saltbox_actions") do |event|
  Dummy::ANNOUNCED << {action: event.payload.fetch(:action).action_name, changes: event.payload.fetch(:changes)}
end
