# The dummy app's base action. It is authorized with Pundit, which
# config.adapters declares; the declaration includes the adapter here.
class ApplicationAction < Saltbox::Actions::Base
  define_verb :cancel, kind: :change, on: :member
  define_verb :postpone, kind: :change, on: :member, idempotent: true
  define_verb :export, kind: :read, plural: true

  summary Event, :id, :title, :starts_on, status: ->(event) { event.status.humanize }
end
