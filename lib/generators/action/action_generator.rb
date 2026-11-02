require "rails/generators"
require "rails/generators/named_base"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g action Event::Update` writes Event::UpdateAction in
      # app/actions/event/update_action.rb and its locale entry, then hands
      # the spec to the test framework (rspec:action with RSpec), the way
      # `rails g model` does. The name is the model, then the action words:
      # - Event::Update or event/update writes Event::UpdateAction;
      # - Event::Type::Create writes Event::Type::CreateAction;
      # - Event::Archive --kind change writes Event::ArchiveAction.
      #
      # An app overrides a template by putting its own at
      # lib/templates/action/action.rb.tt.
      class ActionGenerator < ::Rails::Generators::NamedBase
        namespace "action"
        source_root File.expand_path("templates", __dir__)

        desc "Write an action (app/actions/<model>/<words>_action.rb), its locale entry and its spec"

        class_option :kind, type: :string, enum: %w[read change destructive],
          desc: "The kind of a verb outside the table (read, change or destructive)"
        class_option :id, type: :boolean, default: true,
          desc: "Whether a verb outside the table works on one record named by an id"
        class_option :catalogue, type: :boolean, default: true,
          desc: "Rewrite the committed catalogue (config/actions.json) with the new action"

        hook_for :test_framework

        # @return [void]
        def check_name
          raise Thor::Error, "Name the model and the action: Event::Update, Event::Type::Create" if class_path.empty?
          raise Thor::Error, "#{model_name} is not a model" unless model.is_a?(Class) && model < ActiveRecord::Base
          raise Thor::Error, "#{verb} is spelled #{rails_spelling} in actions" if rails_spelling
          raise Thor::Error, "#{verb} is not a verb in the table: pass --kind read, change or destructive" unless table_verb? || options[:kind]
        end

        # @return [void]
        def write_action
          template "action.rb.tt", File.join(Actions.config.action_paths.first.path.to_s, "#{action_path}_action.rb")
        end

        # @return [void]
        def write_locale_entry
          path = "config/locales/actions.en.yml"
          create_file path, "en:\n  actions:\n" unless File.exist?(File.join(destination_root, path))
          fields = field_names.map { |field| "        #{field}:\n" }.join
          fields = "      fields:\n#{fields}" if fields.present?
          append_to_file path, "    #{action_path}:\n      description:\n#{fields}"
        end

        # @return [void]
        def write_catalogue
          rails_command "actions:catalogue" if behavior == :invoke && options[:catalogue] && !options[:pretend]
        end

        # @return [void]
        def say_next
          say "Write the action's description and its fields' words in config/locales/actions.en.yml, " \
            "then rerun bin/rails actions:catalogue.", :green
          return unless verb == "list" && probe.summary.nil?
          say "Agents get each #{model.model_name.human.downcase}'s full view. To send them a short one, declare " \
            "`summary #{model_name}, :id, ...` in #{base_class}.", :yellow
        end

        private

        def action_path = [*class_path, file_name].join("/")

        def words = file_name.split("_")

        def verb = words.first

        def model_name = class_path.map(&:camelize).join("::")

        def model = model_name.safe_constantize

        def action_class_name = "#{model_name}::#{words.map(&:camelize).join}Action"

        def base_class = Actions.config.base_class

        def table_verb? = Naming::VERBS.key?(verb)

        def rails_spelling = Naming::RAILS_SPELLINGS[verb]

        def kind = table_verb? ? Naming::VERBS.dig(verb, :kind).to_s : options[:kind]

        def takes_id? = table_verb? ? Naming::VERBS.dig(verb, :id) : options[:id]

        def connections = (kind == "destructive") ? :confirm : :allowed

        def record = "@#{model.model_name.singular}"

        def records = "@#{model.model_name.plural}"

        def writes_fields? = Schema::WRITING_VERBS.include?(verb)

        def field_names = writes_fields? ? probe.writable_fields.keys : []

        # An anonymous action class with the new action's name, used to read
        # its fields before its file exists.
        def probe
          @probe ||= begin
            class_name = action_class_name
            Class.new(base_class.constantize) { define_singleton_method(:name) { class_name } }
          end
        end
      end
    end
  end
end
