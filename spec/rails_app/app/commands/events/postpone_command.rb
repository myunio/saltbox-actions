class Events::PostponeCommand < ApplicationCommand
  description "Moves an event to a later day."
  policy_rule :update?

  attribute :starts_on, :date, description: "The new day"
  attribute :reason, :string
  validates :starts_on, presence: true
  validate :later_than_before

  def perform
    event.update!(starts_on:, notes: reason)
    render :show
  end

  private

  def later_than_before
    errors.add(:starts_on, "must be later than the event's day") if starts_on && event.starts_on && starts_on <= event.starts_on
  end
end
