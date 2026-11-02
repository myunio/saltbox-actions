class Event::CancelAction < ApplicationAction
  connections :confirm
  argument :reason, :string

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    @event.update!(status: "cancelled", notes: params[:reason])
    render :show
  end
end
