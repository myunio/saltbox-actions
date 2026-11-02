# The Pundit policy the dummy app's actions ask.
class EventPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = user.can?("events.view")
  def show? = index?
  def create? = user.can?("events.manage")
  def update? = create?
  def cancel? = create?
  def postpone? = create?
  def destroy? = user.can?("events.delete")
  def view_notes? = user.can?("events.notes")

  def permitted_attributes
    fields = %i[title starts_on capacity price featured doors_open_at status parent_id]
    fields << :notes if view_notes?
    fields
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve = @scope.where(org_id: @user.org_id)
  end
end
