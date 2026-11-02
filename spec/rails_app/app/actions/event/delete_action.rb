class Event::DeleteAction < ApplicationAction
  connections :confirm

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    @event.destroy!
    head :no_content
  end
end
