require "rails/generators"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g actions:install` writes the two files an app needs:
      # - config/initializers/saltbox_actions.rb, the configure block with
      #   every optional adapter listed and commented out, each with what it
      #   does and the gem it needs, as Devise's generated initializer lists
      #   its settings. The list comes from Adapters::LIST, so it names every
      #   adapter the gem has;
      # - app/actions/application_action.rb, the base class, unless the app
      #   already has one.
      class InstallGenerator < ::Rails::Generators::Base
        namespace "actions:install"
        source_root File.expand_path("templates", __dir__)

        desc "Write config/initializers/saltbox_actions.rb, listing every optional adapter, and app/actions/application_action.rb"

        def write_initializer
          template "saltbox_actions.rb.tt", "config/initializers/saltbox_actions.rb"
        end

        def write_base_class
          path = "app/actions/application_action.rb"
          template "application_action.rb.tt", path unless File.exist?(File.join(destination_root, path))
        end

        private

        # @return [String] the app's module name, titleized: "Events" for Events::Application
        def app_name = Rails.application ? Rails.application.class.module_parent_name.titleize : "My app"

        # @return [Array<String>] one commented-out line per adapter, aligned
        def adapter_lines
          width = Adapters::LIST.keys.map { it.inspect.size + 1 }.max
          Adapters::LIST.values.map do |adapter|
            needs = adapter.gem ? %(gem "#{adapter.gem}") : "no gem"
            "# #{"#{adapter.name.inspect},".ljust(width)}  # #{adapter.summary} (#{needs})"
          end
        end
      end
    end
  end
end
