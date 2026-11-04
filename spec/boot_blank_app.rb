# Boots a fresh Rails app holding only the README's setup: the initializer
# and the base class, settings and no blocks, and one action. It runs the
# action from the console's line, then prints what it rendered.
# spec/saltbox/actions/blank_app_spec.rb runs it:
#
#   ruby spec/boot_blank_app.rb
require "bundler/setup"
require "tmpdir"
require "fileutils"

root = Dir.mktmpdir("saltbox-actions-blank-app")
at_exit { FileUtils.remove_entry(root) }

# The app's own files, which a scaffolded Rails app with Pundit already has.
app = {
  "config.ru" => "",
  "config/application.rb" => <<~RUBY,
    class Shelf < Rails::Application
      config.eager_load = true
      config.logger = Logger.new(nil)
      config.secret_key_base = "shelf"
    end
  RUBY
  "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\nend\n",
  "app/models/application_record.rb" => "class ApplicationRecord < ActiveRecord::Base\n  primary_abstract_class\nend\n",
  "app/models/user.rb" => "class User < ApplicationRecord\nend\n",
  "app/models/book.rb" => "class Book < ApplicationRecord\nend\n",
  "app/policies/book_policy.rb" => <<~RUBY,
    class BookPolicy
      attr_reader :user, :record

      def initialize(user, record) = (@user, @record = user, record)
      def update? = user.present?
      def permitted_attributes = %i[title]

      class Scope
        def initialize(user, scope) = (@user, @scope = user, scope)
        def resolve = @scope.all
      end
    end
  RUBY
  "app/views/books/show.json.jbuilder" => "json.extract! @book, :id, :title\n"
}

# The setup the README's Install section gives, and its first action.
seam = {
  "config/initializers/saltbox_actions.rb" => <<~RUBY,
    Saltbox::Actions.configure do |config|
      config.adapters = [:pundit]
      config.app_name = "Shelf"
    end
  RUBY
  "app/actions/application_action.rb" => <<~RUBY,
    class ApplicationAction < Saltbox::Actions::Base
    end
  RUBY
  "app/actions/books/update_action.rb" => <<~RUBY
    class Books::UpdateAction < ApplicationAction
      def perform
        book.update!(permitted_attributes(book))
        render :show
      end
    end
  RUBY
}

app.merge(seam).each do |path, source|
  FileUtils.mkdir_p(File.dirname(File.join(root, path)))
  File.write(File.join(root, path), source)
end
puts "seam: #{seam.values.sum { it.lines.size }} lines, #{seam.values.join.scan(/\bdo\b|\{ *\|/).size - 1} blocks besides configure"

require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "jbuilder"
require "pundit"
require "saltbox/actions"

require File.join(root, "config/application")
ENV["DATABASE_URL"] = "sqlite3::memory:"
Shelf.initialize!

ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :name }
  create_table(:books) { |t| t.string :title }
end
User.create!(name: "Ada")
Book.create!(title: "Dume")

result = Books::UpdateAction.perform_now(caller: ApplicationAction::Caller.screen(User.first), id: Book.first.id, title: "Dune")
puts "ran: #{result.status} #{result.body.to_json}"
puts "saved: #{Book.first.title}"
