require "bundler/setup"
require "rails"
require "combustion"
require "rails/test_unit/railtie"
require "jbuilder"
require "pundit"
require "paper_trail"
require "saltbox/actions"
require "saltbox/actions/authorization/pundit"
require "saltbox/actions/controller"

Combustion.path = "spec/rails_app"
Combustion.initialize! :active_record, :action_controller, :action_view do
  config.active_record.logger = nil
  config.eager_load = false
end

require "rails/test_help"
require "saltbox/actions/test_helper"

Rails.application.load_generators
