class Event::ShowNotesAction < ApplicationAction
  connections :never
  authorize :view_notes?

  def perform
    @event = policy_scope(Event).find(params[:id])
    authorize @event
    render :show, with_notes: true
  end
end
