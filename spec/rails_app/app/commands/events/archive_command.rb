class Events::ArchiveCommand < ApplicationCommand
  description "Cancels an event and keeps it on record."
  policy_rule :destroy?

  def perform
    event.update!(status: "cancelled")
    render :show
  end
end
