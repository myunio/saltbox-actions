class Events::ListAction < ApplicationAction
  attribute :status, :string
  validates :status, inclusion: {in: Event.statuses.keys}, allow_nil: true
  paginated

  def perform
    @events = policy_scope(Event).order(:id).offset((page - 1) * page_size).limit(page_size)
    @events = @events.where(status:) if status
    render :index, meta: {page:}
  end
end
