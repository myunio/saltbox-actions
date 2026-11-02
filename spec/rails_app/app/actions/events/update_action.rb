class Events::UpdateAction < ApplicationAction
  def perform
    event.update!(permitted_attributes(event))
    render :show
  end
end
