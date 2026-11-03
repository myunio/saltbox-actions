# The dummy app's base action, authorized with Pundit.
class ApplicationAction < Saltbox::Actions::Base
  include Saltbox::Actions::Authorization::Pundit

  define_verb :cancel, kind: :change, on: :member
  define_verb :postpone, kind: :change, on: :member, idempotent: true

  summary Event, :id, :title, :starts_on, status: ->(event) { event.status.humanize }
end
