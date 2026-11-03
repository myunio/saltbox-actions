module Saltbox
  module Actions
    # Checks what each action declares when an eager-loading app boots
    # (production, CI), without touching the database; adds
    # `rails actions:check` for the rest and `rails actions:dump`; and
    # points `rails g action` at the gem's generator.
    # @api private
    class Railtie < Rails::Railtie
      # What a task that reads the models needs, said when it cannot connect.
      NEEDS_DATABASE = "reads each action's model columns and asks its policy, so it needs the app's database " \
        "(config/database.yml, %{env}). It could not connect: %{error}".freeze

      rake_tasks do
        namespace :actions do
          desc "Check every action against its model, policy and fields (needs the database; run it in CI)"
          task check: :environment do
            Railtie.with_database("actions:check") do
              Rails.application.eager_load!
              Registry.reset!
              puts "All #{Registry.check!.size} actions pass."
            rescue ArgumentError => error
              abort "rails actions:check found problems:\n#{error.message}"
            end
          end

          desc "Write every action as callers see it to the committed catalog (config/actions.json; needs the database)"
          task dump: :environment do
            Railtie.with_database("actions:dump") do
              path = Registry.catalog_path
              path.write(Registry.catalog_json)
              puts "Wrote #{Registry.actions.size} actions to #{path.relative_path_from(Rails.root)}"
            end
          end
        end
      end

      # @param task [String]
      # @yield the task's work
      # @return [void] aborts, naming what the task needs, when the database is unreachable
      def self.with_database(task)
        yield
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError => error
        abort "rails #{task} #{format(NEEDS_DATABASE, env: Rails.env, error: error.message)}"
      end

      config.after_initialize do |app|
        Adapters.install!
        # Rake tasks skip the boot check: rails actions:check runs every
        # check, and a broken action must not stop db:migrate.
        rake_task = defined?(Rake.application) && Rake.application.top_level_tasks.any?
        Registry.actions if app.config.eager_load && !rake_task
      end

      config.to_prepare { Registry.reset! }
    end
  end
end
