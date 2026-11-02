# The Pundit policy the dummy app's actions ask.
class EventPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # The app itself (Caller.system) may read and change events, notes
  # included, but never delete one.
  def index? = system? || user.can?("events.view")
  def show? = index?
  def create? = system? || user.can?("events.manage")
  def update? = create?
  def cancel? = create?
  def postpone? = create?
  def destroy? = !system? && user.can?("events.delete")
  def view_notes? = system? || user.can?("events.notes")

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

    def resolve = @user.is_a?(Saltbox::Actions::SystemAccount) ? @scope.all : @scope.where(org_id: @user.org_id)
  end

  private

  def system? = user.is_a?(Saltbox::Actions::SystemAccount)
end
