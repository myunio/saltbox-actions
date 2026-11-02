# Boots the dummy app as a production web or job process starts: eager
# loading on, the database unreachable (DATABASE_URL names a database
# SQLite cannot open). The boot must not need it. spec/saltbox/actions/boot_spec.rb
# runs it, and with "check" it then runs rails actions:check.
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
Combustion.initialize! :active_record, :action_controller, :action_view, database_reset: false, load_schema: false, database_migrate: false do
  config.active_record.logger = nil
  config.eager_load = true
end

puts "Booted with #{Saltbox::Actions::Registry.actions.size} actions"
if ARGV.include?("check")
  Rails.application.load_tasks
  Rake::Task["actions:check"].invoke
end
