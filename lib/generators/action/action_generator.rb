require "rails/generators"
require "rails/generators/named_base"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g action Event::Update` writes Event::UpdateAction in
      # app/actions/event/update_action.rb and its locale entry, then hands
      # the spec to the test framework (rspec:action with RSpec), the way
      # `rails g model` does. It checks the new action against the boot
      # checks first, and on a problem writes nothing and prints the fix.
      # The name is the model, then the action words:
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

        # A refused check or a failed catalogue step exits 1, so scripts see it.
        #
        # @return [Boolean]
        def self.exit_on_failure? = true

        # Checks the name, then the action the templates would write, as the
        # boot check will: its model, its policy and rule when the base class
        # has an authorization adapter, and its fields. Runs before any file
        # is written.
        #
        # @return [void]
        # @raise [Thor::Error] naming each problem and its fix
        def check
          raise Thor::Error, "Name the model and the action: Event::Update, Event::Type::Create" if class_path.empty?
          raise Thor::Error, "#{model_name} is not a model: generate the model first, or name another" unless model.is_a?(Class) && model < ActiveRecord::Base
          raise Thor::Error, "#{verb} is spelled #{rails_spelling} in actions: bin/rails g action #{model_name}::#{action_words(rails_spelling)}" if rails_spelling
          raise Thor::Error, "#{verb} is not a verb in the table: pass --kind read, change or destructive" unless table_verb? || options[:kind]
          problems = Registry.problems(probe)
          return remember_files if problems.empty?
          raise Thor::Error, "#{action_class_name} would not pass the boot check, so nothing was written:\n" \
            "#{problems.map { "  - #{it}" }.join("\n")}"
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

        hook_for :test_framework do |generator|
          invoke generator, [name], id: takes_id?
        end

        # @return [void]
        # Rewrites the catalogue with the new action. If that fails, every
        # file this generator wrote or changed is put back as it was.
        #
        # @return [void]
        # @raise [Thor::Error] when the catalogue step fails
        def write_catalogue
          return unless behavior == :invoke && options[:catalogue] && !options[:pretend]
          return if rails_command("actions:catalogue")
          restore_files
          raise Thor::Error, "bin/rails actions:catalogue failed, so nothing was written: fix the error above, then run the generator again"
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

        # The files the generator may write or change: the action, the locale
        # file, the test framework's file and the catalogue.
        def touched_paths
          [File.join(Actions.config.action_paths.first.path.to_s, "#{action_path}_action.rb"),
            "config/locales/actions.en.yml",
            File.join("spec/actions", "#{action_path}_action_spec.rb"),
            File.join("test/actions", "#{action_path}_action_test.rb"),
            Actions.config.catalogue_path.to_s]
        end

        # Notes each file's contents (nil when it does not exist) before any is written.
        def remember_files
          @remembered = touched_paths.to_h do |path|
            full = File.expand_path(path, destination_root)
            [full, File.exist?(full) ? File.binread(full) : nil]
          end
        end

        # Puts each file back as remember_files found it.
        def restore_files
          @remembered.each do |full, contents|
            if contents
              File.binwrite(full, contents)
            elsif File.exist?(full)
              File.delete(full)
            end
          end
          say_status :restore, "removed what this generator wrote", :red
        end

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

        # Agents ask before a new change or destructive action unless the
        # app sets Configuration#default_connections, which then applies.
        #
        # @return [Symbol, nil] the connections to write, nil to leave it to the app's default
        def connections
          default = Actions.config.default_connections
          return if default && !(kind == "destructive" && default == :allowed)
          (kind == "read") ? :allowed : :confirm
        end

        def action_words(spelling) = [spelling, *words.drop(1)].map(&:camelize).join

        def record = "@#{model.model_name.singular}"

        def records = "@#{model.model_name.plural}"

        def writes_fields? = Schema::WRITING_VERBS.include?(verb)

        def field_names = writes_fields? ? probe.writable_fields.keys : []

        # An anonymous action class with the new action's name and the
        # declarations the template writes, used to check it and read its
        # fields before its file exists.
        def probe
          @probe ||= begin
            class_name = action_class_name
            declared_kind = kind.to_sym unless table_verb?
            id = !table_verb? && takes_id?
            rule = :"#{verb}?" if words.size > 1 || !table_verb?
            rule_for_connections = connections
            Class.new(base_class.constantize) do
              define_singleton_method(:name) { class_name }
              kind declared_kind if declared_kind
              argument :id if id
              connections rule_for_connections if rule_for_connections
              authorize rule if rule
            end
          end
        end
      end
    end
  end
end
