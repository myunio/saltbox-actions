require "saltbox/actions/paper_trail"

# The dummy app's choices, as an app writes them. ANNOUNCED keeps each
# change's records, so specs can see what on_changes received.
module Dummy
  ANNOUNCED = []
end

Saltbox::Actions.configure do |config|
  config.app_name = "Dummy"
  config.instructions = "Dummy keeps events. Call find_action for anything not listed."
  config.max_array_items = 50
  config.require_area = true
  config.area_for { |model| {"Event" => "events", "Billing::Invoice" => "billing"}[model.name] }
  config.permissions_held { |caller| (caller.account.permissions == :all) ? [] : caller.account.permissions }
  config.schema_principal { |run| run.call(Account.new(id: 0, permissions: :all)) }
  config.around_run do |invocation, run|
    Saltbox::Actions::PaperTrail.request(invocation, agent: invocation.caller.agent,
      surface: invocation.caller.surface, invocation_id: invocation.invocation_id) { run.call }
  end
  config.on_changes { |changes, invocation| Dummy::ANNOUNCED << {action: invocation.action.action_name, changes:} }
end

Rails.application.config.after_initialize { Saltbox::Actions::PaperTrail.install! }
