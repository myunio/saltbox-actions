require "rails/generators"
require "rails/generators/active_record/migration"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g actions:approvals` writes the action_approvals migration and
      # the ActionApproval model, which includes
      # Adapters::Confirmation::Approvals, as Devise's generator writes its
      # users migration. The app then declares :approvals, points its
      # confirm hook at the model, and adds the screen where a person
      # approves their agents' requests.
      class ApprovalsGenerator < ::Rails::Generators::Base
        include ::ActiveRecord::Generators::Migration

        namespace "actions:approvals"
        source_root File.expand_path("templates", __dir__)

        desc "Write the action_approvals migration and the ActionApproval model, for agents' calls to :confirm actions"

        class_option :approver, type: :string, default: "user",
          desc: "The association that holds the person who approves: the caller's user (account in an app of accounts)"
        class_option :connections, type: :string,
          desc: "The table the caller's connection lives in (oauth_connections), for a foreign key; none when left out"
        class_option :tenant, type: :string,
          desc: "The tenant each approval belongs to (org): a column, a foreign key and acts_as_tenant when the app has it"
        class_option :primary_key_type, type: :string,
          desc: "The primary key type (uuid); the app's generator setting when left out"

        def write_migration
          migration_template "migration.rb.tt", File.join(db_migrate_path, "create_action_approvals.rb")
        end

        def write_model
          template "model.rb.tt", "app/models/action_approval.rb"
        end

        def say_next_steps
          say <<~TEXT

            Next, in config/initializers/saltbox_actions.rb:

              config.adapters = [..., :approvals]
              config.confirm { |invocation, action| ActionApproval.redeem!(invocation, action) }

            Then give the person a screen of their requests, ActionApproval.pending
            where #{approver} is them, that approves one (approve!) or declines it (destroy!).
          TEXT
        end

        private

        # @return [String] the approver association's name
        def approver = options[:approver].underscore

        # @return [String, nil] the tenant association's name
        def tenant = options[:tenant]&.underscore

        # @return [Boolean] whether the app has acts_as_tenant, which scopes
        #   the model to the current tenant
        def acts_as_tenant? = defined?(::ActsAsTenant) ? true : false

        # @return [String, nil] the key type, from the option or the app's
        #   `config.generators` (`g.orm :active_record, primary_key_type: :uuid`)
        def key_type
          options[:primary_key_type] || (Rails.application && Rails.application.config.generators.options.dig(:active_record, :primary_key_type))
        end

        def primary_key_type = key_type && ", id: :#{key_type}"

        def foreign_key_type = key_type && ", type: :#{key_type}"

        # A connection's approval goes with it.
        def connection_foreign_key
          options[:connections] && ", foreign_key: {to_table: :#{options[:connections]}, on_delete: :cascade}"
        end

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
