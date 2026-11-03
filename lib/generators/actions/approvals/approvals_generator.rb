require "rails/generators"
require "rails/generators/active_record/migration"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g actions:approvals` writes the migration for the gem's
      # saltbox_action_approvals table, as `rails active_storage:install`
      # does for Active Storage's. The model, Saltbox::Actions::Approval, is
      # the gem's. Its foreign keys follow Configuration#approvals: the
      # user's table, the tenant's, and the connection's.
      class ApprovalsGenerator < ::Rails::Generators::Base
        include ::ActiveRecord::Generators::Migration

        namespace "actions:approvals"
        source_root File.expand_path("templates", __dir__)

        desc "Write the migration for saltbox_action_approvals, the :approvals adapter's table"

        class_option :primary_key_type, type: :string,
          desc: "The primary key type (uuid); the app's generator setting when left out"

        def write_migration
          migration_template "migration.rb.tt", File.join(db_migrate_path, "create_saltbox_action_approvals.rb")
        end

        def say_next_steps
          say <<~TEXT

            Next, in config/initializers/saltbox_actions.rb:

              config.adapters = [..., :approvals]
              config.approvals = {user: "#{settings.fetch(:user)}"#{", tenant: \"#{settings[:tenant]}\"" if settings[:tenant]}}

            Then give the person a screen of their requests,
            Saltbox::Actions::Approval.waiting_for(person), that approves one
            (approve!) or declines it (destroy!).
          TEXT
        end

        private

        # @return [Hash] the app's config.approvals
        def settings = Actions.config.approvals

        # @param class_name [String, nil]
        # @return [String, nil] the class's table: its own when it loads, else the conventional one
        def table_for(class_name)
          return unless class_name
          class_name.constantize.table_name
        rescue NameError
          class_name.underscore.tr("/", "_").pluralize
        end

        def user_table = table_for(settings.fetch(:user))

        def tenant_table = table_for(settings[:tenant])

        def connection_table = table_for(settings[:connection])

        # @return [String, nil] the key type, from the option or the app's
        #   `config.generators` (`g.orm :active_record, primary_key_type: :uuid`)
        def key_type
          options[:primary_key_type] || (Rails.application && Rails.application.config.generators.options.dig(:active_record, :primary_key_type))
        end

        def primary_key_type = key_type && ", id: :#{key_type}"

        def foreign_key_type = key_type && ", type: :#{key_type}"

        # @return [String] jsonb on PostgreSQL, json elsewhere
        def json_type
          config = defined?(ActiveRecord::Base) && Rails.application && ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).first
          config&.adapter.to_s.start_with?("postgres") ? "jsonb" : "json"
        end

        def migration_version = "[#{ActiveRecord::Migration.current_version}]"
      end
    end
  end
end
