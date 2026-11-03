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
    # It has no model, so Reports would be its policy namespace; every
    # reader of events may count them, through EventPolicy.
    policy_namespace false
    permission "events.view", any_of("events.manage", "events.delete")
    summary :count
    output_schema({type: "object", properties: {count: {type: "integer"}}, required: ["count"]})

    attribute :status, :string, description: "Only events with this status"
    attribute :page, :integer, description: "Page number, from 1"
    validates :status, inclusion: {in: %w[draft published cancelled]}, allow_nil: true
    validates :page, numericality: {greater_than_or_equal_to: 1}, allow_nil: true

    cli "events count", aliases: ["events tally"], args: %w[status]

    def perform
      skip_authorization
      events = policy_scope(Event)
      events = events.where(status:) if status
      render json: {count: events.count}, meta: {page: page || 1}
    end
  end
end
