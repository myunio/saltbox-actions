# Boots a fresh Rails app in a folder of its own, eager loading off, as a
# development server, console or runner does, and prints what its actions
# do. Its base class is defined in an initializer that runs before the one
# that declares the adapters, and its action reloads from app/actions.
# spec/saltbox/actions/lazy_boot_spec.rb runs it:
#
#   ruby spec/boot_lazy_app.rb ADAPTER [reload]
require "bundler/setup"
require "tmpdir"
require "fileutils"

adapter = ARGV.fetch(0)
root = Dir.mktmpdir("saltbox-actions-lazy-app")
at_exit { FileUtils.remove_entry(root) }

files = {
  "config.ru" => "",
  "config/application.rb" => <<~RUBY,
    class LazyApp < Rails::Application
      config.eager_load = false
      config.enable_reloading = true
      config.logger = Logger.new(nil)
      config.secret_key_base = "lazy"
    end
  RUBY
  "config/initializers/00_early.rb" => <<~RUBY,
    # Defined before config/initializers/actions.rb declares the adapters.
    class ApplicationAction < Saltbox::Actions::Base; end
  RUBY
  "config/initializers/actions.rb" => <<~RUBY,
    Saltbox::Actions.configure { |config| config.adapters = [:#{adapter}] }
  RUBY
  "app/actions/list_widgets_action.rb" => <<~RUBY
    # Never calls authorize or policy_scope; WORK says whether perform ran.
    class ListWidgetsAction < ApplicationAction
      permission :everyone

      def perform
        WORK << :performed
        head :no_content
      end
    end
  RUBY
}
files.each do |path, source|
  FileUtils.mkdir_p(File.dirname(File.join(root, path)))
  File.write(File.join(root, path), source)
end

require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require adapter.to_s
require "saltbox/actions"

require File.join(root, "config/application")
ENV["DATABASE_URL"] = "sqlite3::memory:"
WORK = []
LazyApp.initialize!

def run
  WORK.clear
  ListWidgetsAction.perform_now(caller: Saltbox::Actions::Caller.screen(Object.new))
  "ran #{WORK.inspect}"
rescue => error
  "#{error.class}, perform ran: #{WORK.any?}"
end

puts "first: #{run}"
if ARGV.include?("reload")
  before = ListWidgetsAction
  Rails.application.reloader.reload!
  puts "reloaded: #{!ListWidgetsAction.equal?(before)}"
  puts "after reload: #{run}"
end
