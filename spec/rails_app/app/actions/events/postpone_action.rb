# A verb the app adds (define_verb in ApplicationAction), with attributes
# that are not the policy's fields.
class Events::PostponeAction < ApplicationAction
  description <<~TEXT
    Use this when the person wants an event moved to a later day.
    Returns the event.
  TEXT

  attribute :starts_on, :date, description: "The new first day"
  attribute :reason, :string
  validates :starts_on, presence: true
  validates :reason, length: {maximum: 200}

  def perform
    event.update!(starts_on:, notes: reason)
    render :show
  end
end
