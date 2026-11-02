# The dummy app's base action, authorized with Pundit.
class ApplicationAction < Saltbox::Actions::Base
  include Saltbox::Actions::Authorization::Pundit
end
