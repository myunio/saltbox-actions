require "spec_helper"
require "bundler/setup"
require "rails"
require "combustion"
require "jbuilder"
require "pundit"
require "action_policy"
require "paper_trail"
require "saltbox/actions"

require_relative "rails_app/engines/billing/lib/billing"

Combustion.path = "spec/rails_app"
Combustion.initialize! :active_record, :action_controller, :action_view, :active_job do
  config.active_record.logger = nil
  config.active_job.queue_adapter = :test
  config.eager_load = false
end

require "rspec/rails"
require "saltbox/actions/adapters/testing/rspec"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { require it }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.before { Dummy::ANNOUNCED.clear }

  # An app declares one authorization adapter, which every action then has,
  # so the suite runs once for each (SALTBOX_ACTIONS_AUTHORIZATION, see the
  # Rakefile). Examples tagged authorization: run in that pass alone; the
  # rest run in the Pundit pass.
  authorization = ENV.fetch("SALTBOX_ACTIONS_AUTHORIZATION", "pundit").to_sym
  if authorization == :pundit
    config.filter_run_excluding authorization: ->(value) { value && value != :pundit }
  else
    config.filter_run_including authorization:
  end
end
