# An action whose name, title, CLI command and permissions are declared, as
# in an app whose names were public before it used the gem.
module Reports
  class CountEventsAction < ApplicationAction
    action_name "count_events"
    title "Count events"
    description <<~TEXT
      Use this when the person asks how many events there are, or how many have a status.
      Returns the count.
    TEXT
    kind :read
    connections :allowed
    permission "events.view", any_of("events.manage", "events.delete")
    argument :status, :string, enum: %w[draft published cancelled], description: "Only events with this status"
    argument :page, :integer, minimum: 1, description: "Page number, from 1"
    cli "events count", aliases: ["events tally"], args: %w[status], columns: %w[count]
    returns({type: "object", properties: {count: {type: "integer"}}, required: ["count"]})

    def perform
      skip_authorization
      events = policy_scope(Event)
      events = events.where(status: params[:status]) if params[:status]
      render json: {count: events.count}, meta: {page: params[:page] || 1}
    end
  end
end
