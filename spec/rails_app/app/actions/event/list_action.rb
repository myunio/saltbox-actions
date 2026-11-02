class Event::ListAction < ApplicationAction
  connections :allowed
  argument :status, :string, enum: Event.statuses.keys
  argument :page, :integer, minimum: 1, default: 1

  def perform
    authorize Event
    @events = policy_scope(Event).order(:id).offset((params[:page] - 1) * 25).limit(25)
    @events = @events.where(status: params[:status]) if params[:status]
    render :index, meta: {page: params[:page]}
  end
end
