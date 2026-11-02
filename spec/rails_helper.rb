require "spec_helper"
require "bundler/setup"
require "rails"
require "combustion"
require "jbuilder"
require "pundit"
require "action_policy"
require "paper_trail"
require "saltbox/actions"
require "saltbox/actions/authorization/pundit"
require "saltbox/actions/authorization/action_policy"
require "saltbox/actions/controller"

require_relative "rails_app/engines/billing/lib/billing"

Combustion.path = "spec/rails_app"
Combustion.initialize! :active_record, :action_controller, :action_view do
  config.active_record.logger = nil
  config.eager_load = false
end

require "rspec/rails"
require "saltbox/actions/rspec"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { require it }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.before { Dummy::ANNOUNCED.clear }
end
