module Saltbox
  module Actions
    # Checks every action when an eager-loading app boots (production, CI),
    # adds `rails actions:catalogue`, and points `rails g action` at the
    # gem's generator.
    class Railtie < Rails::Railtie
      rake_tasks do
        namespace :actions do
          desc "Write every action as callers see it to the committed catalogue (config/actions.json)"
          task catalogue: :environment do
            path = Registry.catalogue_path
            path.write(Registry.catalogue_json)
            puts "Wrote #{Registry.actions.size} actions to #{path.relative_path_from(Rails.root)}"
          end
        end
      end

      config.after_initialize do |app|
        # Rake tasks skip the checks. They read the models' columns, and a
        # task such as db:prepare boots before the migrations it runs: a
        # column a migration adds must not stop that migration.
        rake_task = defined?(Rake.application) && Rake.application.top_level_tasks.any?
        Registry.actions if app.config.eager_load && !rake_task
      end

      config.to_prepare { Registry.reset! }
    end
  end
end
