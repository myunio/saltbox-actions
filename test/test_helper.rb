require "bundler/setup"
require "rails"
require "combustion"
require "rails/test_unit/railtie"
require "jbuilder"
require "pundit"
require "paper_trail"
require "saltbox/actions"

require_relative "../spec/rails_app/engines/billing/lib/billing"

Combustion.path = "spec/rails_app"
Combustion.initialize! :active_record, :action_controller, :action_view, :active_job do
  config.active_record.logger = nil
  config.eager_load = false
end

require "rails/test_help"
require "saltbox/actions/adapters/testing/minitest"

Rails.application.load_generators
