require "rails/generators"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g actions:install` writes config/initializers/saltbox_actions.rb: the
      # configure block with every optional adapter listed and commented
      # out, each with what it does and the gem it needs, as Devise's
      # generated initializer lists its settings. The list comes from
      # Adapters::LIST, so it names every adapter the gem has.
      class InstallGenerator < ::Rails::Generators::Base
        namespace "actions:install"
        source_root File.expand_path("templates", __dir__)

        desc "Write config/initializers/saltbox_actions.rb, listing every optional adapter"

        def write_initializer
          template "saltbox_actions.rb.tt", "config/initializers/saltbox_actions.rb"
        end

        # An initializer from before 1.1 also configures the gem, and
        # whichever loads last decides a setting both make.
        def warn_about_old_initializer
          return unless File.exist?(File.join(destination_root, "config/initializers/actions.rb"))
          say_status :warning, "config/initializers/actions.rb may also configure saltbox-actions: " \
            "move its settings into config/initializers/saltbox_actions.rb and remove it", :yellow
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
