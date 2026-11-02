class Events::ExportCommand < ApplicationCommand
  description "Counts the events the person can see, for a report."
  policy_rule :index?

  attribute :status, :string
  validates :status, inclusion: {in: Event.statuses.keys}, allow_nil: true

  def perform
    authorize Event
    events = policy_scope(Event)
    events = events.where(status:) if status
    render json: {count: events.count}
  end
end
