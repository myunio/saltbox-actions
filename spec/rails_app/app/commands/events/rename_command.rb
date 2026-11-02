class Events::RenameCommand < ApplicationCommand
  description "Changes an event's title, and its notes for those who may read them."
  policy_rule :update?
  accepts :title, :notes, :parent

  def perform
    event.update!(accepted_attributes)
    render :show
  end

  private

  def find_event(events) = events.where.not(status: "cancelled").find(id)
end
