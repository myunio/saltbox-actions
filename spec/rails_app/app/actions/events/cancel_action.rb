class Events::CancelAction < ApplicationAction
  connections :confirm
  attribute :reason, :string

  def perform
    event.update!(status: "cancelled", notes: reason)
    render :show
  end
end
