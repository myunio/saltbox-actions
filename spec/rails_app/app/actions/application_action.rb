# The dummy app's base action. It is authorized with Pundit, which
# config.adapters declares; the declaration includes the adapter here.
class ApplicationAction < Saltbox::Actions::Base
  define_verb :cancel, kind: :change, on: :member
  define_verb :postpone, kind: :change, on: :member, idempotent: true
  define_verb :export, kind: :read, plural: true

  summary Event, :id, :title, :starts_on, status: ->(event) { event.status.humanize }

  # The permission names the person holds, for actions that declare them.
  def self.permissions_held(caller)
    return [] if caller.system? || caller.user.permissions == :all
    caller.user.permissions
  end

  # The catalog's schema is built for a person holding every permission.
  def self.with_schema_user = yield(User.new(id: 0, permissions: :all))

  # A dummy User is a plain object, so its org is found by id.
  def current_tenant = current_user.respond_to?(:org_id) ? Org.find_or_create_by!(id: current_user.org_id) : super

  private

  # Tokens are not checked in the dummy app: every caller stands as it is.
  def refresh_caller = current_caller

  def info_for_paper_trail = {agent: current_caller.agent_name, surface: current_caller.surface, invocation_id:}
end
