class Event::UpdateAction < ApplicationAction
  connections :allowed
  idempotent

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    @event.update!(permitted_attributes(@event))
    render :show
  end
end
