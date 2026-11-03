# Boots the dummy app as a console, a runner or a development job does:
# routes load lazily, on first use. Then renders a view with a *_url
# helper, as the first thing the process does.
# spec/saltbox/actions/url_options_spec.rb runs it.
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

link = Class.new(ApplicationAction) do
  define_singleton_method(:name) { "LinkAction" }
  permission :everyone
  kind :read

  def perform
    skip_authorization
    skip_policy_scope
    render "links/show"
  end
end
2.times { puts Saltbox::Actions::Invocation.call(action: link, caller: Saltbox::Actions::Caller.system, arguments: {}).body["url"] }
