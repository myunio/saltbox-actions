class Events::CancelAction < ApplicationAction
  agents :confirm
  attribute :reason, :string

  def perform
    event.update!(status: "cancelled", notes: reason)
    render :show
  end
end
