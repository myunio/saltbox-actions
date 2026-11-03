require "rails/generators"
require "rails/generators/named_base"
require "saltbox/actions"

module Saltbox
  module Actions
    module Generators
      # `rails g action Events::Update` writes Events::UpdateAction in
      # app/actions/events/update_action.rb, then hands the spec to the test
      # framework (rspec:action with RSpec), the way `rails g model` does. It
      # checks the new action against the boot checks first, and on a problem
      # writes nothing and prints the fix. The name is the resource, then the
      # action words, as a controller is named; a singular resource is made
      # plural, as `rails g scaffold_controller` does:
      # - Events::Update, events/update or Event::Update writes Events::UpdateAction;
      # - Event::Types::Create writes Event::Types::CreateAction;
      # - Events::Archive --kind change writes Events::ArchiveAction.
      # A verb the app adds with define_verb needs no --kind.
      #
      # An app overrides a template by putting its own at
      # lib/templates/action/action.rb.tt.
      class ActionGenerator < ::Rails::Generators::NamedBase
        namespace "action"
        source_root File.expand_path("templates", __dir__)

        desc "Write an action (app/actions/<resources>/<words>_action.rb) and its spec"

        class_option :kind, type: :string, enum: %w[read change destructive],
          desc: "The kind of a verb outside the verb table (read, change or destructive)"
        class_option :id, type: :boolean, default: true,
          desc: "Whether a verb outside the verb table works on one record named by an id"
        class_option :catalog, type: :boolean, default: true,
          desc: "Rewrite the committed catalog (config/actions.json) with the new action"

        # A refused check or a failed catalog step exits 1, so scripts see it.
        #
        # @return [Boolean]
        def self.exit_on_failure? = true

        # Checks the name, then the action the template would write, as
        # rails actions:check will: its model, its policy and rule when the
        # base class has an authorization adapter, and its fields. Runs
        # before any file is written.
        #
        # @return [void]
        # @raise [Thor::Error] naming each problem and its fix
        def check
          raise Thor::Error, "Name the resource and the action: Events::Update, Event::Types::Create" if class_path.empty?
          raise Thor::Error, "#{resource_name} names no model (#{model_name} is not one): generate the model first, or name another" unless model.is_a?(Class) && model < ActiveRecord::Base
          raise Thor::Error, "#{verb} is spelled #{rails_spelling} in actions: bin/rails g action #{resource_name}::#{action_words(rails_spelling)}" if rails_spelling
          raise Thor::Error, "#{verb} is not a verb in the table: pass --kind read, change or destructive, or add it with define_verb" unless verb_rule || options[:kind]
          problems = Registry.problems(probe)
          return remember_files if problems.empty?
          raise Thor::Error, "#{action_class_name} would not pass rails actions:check, so nothing was written:\n" \
            "#{problems.map { "  - #{it}" }.join("\n")}"
        end

        # @return [void]
        def write_action
          template "action.rb.tt", File.join(Actions.config.action_paths.first.path.to_s, "#{action_path}_action.rb")
        end

        hook_for :test_framework do |generator|
          invoke generator, ["#{resource_name}::#{words.map(&:camelize).join}"], id: takes_id?
        end

        # Rewrites the catalog with the new action. If that fails, every
        # file this generator wrote or changed is put back as it was.
        #
        # @return [void]
        # @raise [Thor::Error] when the catalog step fails
        def write_catalog
          return unless behavior == :invoke && options[:catalog] && !options[:pretend]
          return if rails_command("actions:dump")
          restore_files
          raise Thor::Error, "bin/rails actions:dump failed, so nothing was written: fix the error above, then run the generator again"
        end

        # @return [void]
        def say_next
          say "Tell agents when to use it: write its description in the class.", :green
          undescribed = probe.input_schema["properties"].reject { |_, schema| schema.key?("description") }.keys
          if undescribed.any?
            say "Describe #{undescribed.to_sentence} for agents in config/locales/actions.en.yml, under actions.#{probe.resource_locale_key}.fields, " \
              "then rerun bin/rails actions:dump.", :green
          end
          if accepted_references.present?
            say "Left #{accepted_references.to_sentence} out of accepts: a caller could point #{(accepted_references.size > 1) ? "them" : "it"} " \
              "at any record it can see. Accept #{(accepted_references.size > 1) ? "one" : "it"} only if that is safe.", :yellow
          end
          return unless verb == "list" && probe.summary.nil?
          say "Agents get each #{model.model_name.human.downcase}'s full view. To send them a short one, declare " \
            "`summary #{model_name}, :id, ...` in #{base_class}.", :yellow
        end

        private

        # The files the generator may write or change: the action, the test
        # framework's file and the catalog.
        def touched_paths
          [File.join(Actions.config.action_paths.first.path.to_s, "#{action_path}_action.rb"),
            File.join("spec/actions", "#{action_path}_action_spec.rb"),
            File.join("test/actions", "#{action_path}_action_test.rb"),
            Actions.config.catalog_path.to_s]
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

        # The resource's folders, the last one plural: ["events"], ["event", "types"].
        def resource_path = [*class_path[0...-1], class_path.last.pluralize]

        def action_path = [*resource_path, file_name].join("/")

        def words = file_name.split("_")

        def verb = words.first

        def resource_name = resource_path.map(&:camelize).join("::")

        def model = Naming.model_for(resource_name)

        def model_name = model&.name || resource_name.classify

        def action_class_name = "#{resource_name}::#{words.map(&:camelize).join}Action"

        def base_class = Actions.config.base_class

        def verb_rule = base_class.constantize.verbs[verb]

        def rails_spelling = Naming::RAILS_SPELLINGS[verb]

        def kind = verb_rule ? verb_rule[:kind].to_s : options[:kind]

        def takes_id? = verb_rule ? verb_rule[:member] : options[:id]

        def action_words(spelling) = [spelling, *words.drop(1)].map(&:camelize).join

        def record = model.model_name.param_key

        def records = "@#{model.model_name.plural}"

        def policy_rule = (:"#{verb}?" if words.size > 1 || !verb_rule)

        # @return [Array<String>] the lines the template declares at the top of the class
        def declarations
          lines = []
          lines << "kind :#{kind}" unless verb_rule
          lines << "attribute :id" if !verb_rule && takes_id?
          lines << "policy_rule :#{policy_rule}" if policy_rule
          lines << "accepts #{accepted.map { ":#{it}" }.join(", ")}" if accepted.present?
          if accepted_references.present?
            lines << "# A caller may point a reference at any record it can see: accept one only if that is safe."
            lines << "# accepts #{accepted_references.map { ":#{it}" }.join(", ")}"
          end
          lines
        end

        # The model fields a create or update names with `accepts` when the
        # base class's authorization adapter does not supply them: every
        # column the person could set, to trim, as a scaffold's params list
        # does. A belongs_to is left out (accepted_references): with no
        # policy, a caller could point it at any record it can see, such as
        # another person as a record's owner. Nil when the adapter supplies
        # them, or for any other verb.
        def accepted
          return unless Schema::WRITING_VERBS.include?(verb) && !bare_probe.supplies_fields?
          skipped = [model.primary_key, "created_at", "updated_at", *references.keys]
          model.column_names - skipped
        end

        # @return [Array<String>, nil] the belongs_to fields the template leaves commented out, by association name
        def accepted_references = (references.values if accepted)

        def references = model.reflect_on_all_associations(:belongs_to).to_h { [it.foreign_key.to_s, it.name.to_s] }

        # An anonymous action class with the new action's name and the
        # declarations the template writes, used to check it and read its
        # fields before its file exists.
        def probe
          @probe ||= begin
            fields = accepted
            bare_probe.tap { |action| action.accepts(*fields) if fields.present? }
          end
        end

        def bare_probe
          @bare_probe ||= begin
            class_name = action_class_name
            declared_kind = kind.to_sym unless verb_rule
            id = !verb_rule && takes_id?
            rule = policy_rule
            Class.new(base_class.constantize) do
              define_singleton_method(:name) { class_name }
              kind declared_kind if declared_kind
              attribute :id if id
              policy_rule rule if rule
            end
          end
        end
      end
    end
  end
end
