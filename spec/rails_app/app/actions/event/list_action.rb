class Event::ListAction < ApplicationAction
  connections :allowed
  argument :status, :string, enum: Event.statuses.keys

  def perform
    authorize Event
    @events = policy_scope(Event).order(:id)
    @events = @events.where(status: params[:status]) if params[:status]
    render :index
  end
end
