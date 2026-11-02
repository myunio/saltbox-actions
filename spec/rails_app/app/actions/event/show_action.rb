class Event::ShowAction < ApplicationAction
  connections :allowed
  mcp_core

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    render :show
  end
end
