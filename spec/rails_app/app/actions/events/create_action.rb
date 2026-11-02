class Events::CreateAction < ApplicationAction
  summary :id, :title, :starts_on

  def perform
    @event = policy_scope(Event).new(permitted_attributes(Event).merge(org_id: account.org_id))
    authorize @event
    @event.save!
    render :show, status: :created
  end
end
