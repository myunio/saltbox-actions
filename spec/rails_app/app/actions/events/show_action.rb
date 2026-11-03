class Events::ShowAction < ApplicationAction
  featured

  def perform
    render :show
  end
end
