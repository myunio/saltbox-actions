# The dummy app's base action, authorized with Pundit.
class ApplicationAction < Saltbox::Actions::Base
  include Saltbox::Actions::Authorization::Pundit

  summary Event, :id, :title, :starts_on, status: ->(event) { event.status.humanize }
end
