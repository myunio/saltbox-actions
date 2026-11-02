class Events::DeleteAction < ApplicationAction
  def perform
    event.destroy!
    head :no_content
  end
end
