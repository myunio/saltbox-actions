module Saltbox
  module Actions
    # Loads every action under the actions folder and checks its settings
    # when the app boots. A setting the class name cannot give, and the class
    # does not declare, stops the boot in CI and production instead of being
    # guessed. Each error names the action and the fix.
    module Registry
      # @return [Array<Class>] every action, sorted by name
      def self.actions
        @actions ||= begin
          entries = (Actions.config.every_file_an_action ? action_files.map { |path| action_at(path) } : descendants).sort_by(&:action_name)
          validate!(entries)
          entries.freeze
        end
      end

      # @return [void] forgets the loaded actions, so the next call loads them again
      def self.reset! = @actions = @version = nil

      # @return [Pathname] the actions folder
      def self.root = Rails.root.join(Actions.config.actions_path)

      # The files under the actions folder, without the base class's own file
      # and folder (application_action.rb and application_action/), which hold
      # shared code.
      #
      # @return [Array<String>] action file paths
      # @raise [ArgumentError] for a file under the actions folder that is not an action
      def self.action_files
        support = Actions.config.base_class.underscore
        files = Dir[root.join("**/*.rb").to_s].reject do |path|
          relative = Pathname(path).relative_path_from(root).to_s
          relative == "#{support}.rb" || relative.start_with?("#{support}/")
        end
        misnamed = files.reject { it.end_with?("_action.rb") }
        raise ArgumentError, "Every file under #{Actions.config.actions_path}/ ends _action.rb: rename or move #{misnamed.map { relative(it) }.join(", ")}" if misnamed.any?
        files
      end

      # For an app whose actions folder holds other files too
      # (Configuration#every_file_an_action off): the base class's named
      # subclasses, once the folder is loaded. Only the class its name now
      # points to counts, not one a code reload replaced.
      #
      # @return [Array<Class>]
      def self.descendants
        Rails.autoloaders.main.eager_load_dir(root.to_s)
        Actions.config.base.descendants.select { |action| action.name&.safe_constantize.equal?(action) }
      end

      # The action class a file defines, found by the constant Zeitwerk
      # expects at its path. It must be defined in that file: a model whose
      # name ends in Action, loaded first from app/models/, would otherwise
      # take the action's place.
      #
      # @param path [String]
      # @return [Class]
      # @raise [ArgumentError] when the file does not define the action class its path names
      def self.action_at(path)
        name = Rails.autoloaders.main.cpath_expected_at(path)
        constant = name.safe_constantize
        base = Actions.config.base_class
        unless constant.is_a?(Class) && constant < base.constantize && Object.const_source_location(name)&.first == path
          raise ArgumentError, "#{relative(path)} must define #{name} < #{base}; " \
            "#{constant ? "#{name} is defined in #{Object.const_source_location(name)&.first&.then { relative(it) }}" : "it defines nothing of that name"}"
        end
        constant
      end

      # @param entries [Array<Class>]
      # @return [void]
      # @raise [ArgumentError] naming every problem with each action
      def self.validate!(entries)
        Actions.config.registry_checks.each { it.call(entries) }
        duplicates = entries.group_by(&:action_name).select { |_, actions| actions.size > 1 }
        raise ArgumentError, "Action names must be unique: #{duplicates.keys.join(", ")}" if duplicates.any?
        problems = entries.flat_map { |action| problems(action).map { "#{action.name}: #{it}" } }
        raise ArgumentError, problems.join("\n") if problems.any?
      end

      # @param action [Class]
      # @return [Array<String>] what is wrong with the action, and the fix
      def self.problems(action)
        return named_problems(action) if action.declared_name
        verb = action.verb
        problems = []
        if (spelling = Naming::RAILS_SPELLINGS[verb])
          renamed = action.name.sub(/#{verb.camelize}(?=[A-Z]|Action\z)/, spelling.camelize)
          return ["#{verb} is spelled #{spelling} in actions: rename it #{renamed}"]
        end
        if action.table_verb?
          problems << "#{verb} is a verb in the table, so its kind is #{Naming::VERBS.dig(verb, :kind)}: remove kind" if action.declared_kind
          if action.arguments.key?("id")
            problems << (Naming::VERBS.dig(verb, :id) ? "#{verb} already takes an id: remove argument :id" : "#{verb} takes no id: name the record in another argument")
          end
        elsif action.declared_kind.nil?
          problems << "#{verb} is not a verb in the table: declare kind :read, :change or :destructive"
        end
        problems.concat(connection_problems(action))
        problems.concat(model_problems(action))
        problems.concat(Actions.config.action_checks.flat_map { Array(it.call(action)) })
      end

      # @param action [Class]
      # @return [Array<String>] what is wrong with its connections declaration
      def self.connection_problems(action)
        return ["declare connections :allowed, :confirm or :never"] unless action.connections
        return ["a destructive action is never connections :allowed: use :confirm, or :never"] if action.kind == :destructive && action.connections == :allowed
        []
      end

      # An action with a declared name answers to no verb table: it declares
      # its kind, and its policy is checked only when it declares a model.
      #
      # @param action [Class]
      # @return [Array<String>]
      def self.named_problems(action)
        problems = []
        problems << "declare kind :read, :change or :destructive" unless action.declared_kind
        problems.concat(connection_problems(action))
        if action.model && action.declared_query.nil?
          problems << "#{action.model.name} is its model: name the policy rule, authorize :show? or another"
        elsif action.model
          problems.concat(model_problems(action))
        end
        problems.concat(Actions.config.action_checks.flat_map { Array(it.call(action)) })
      end

      # @param action [Class]
      # @return [Array<String>] what is wrong with the action's model, policy and fields, and the fix
      def self.model_problems(action)
        return [] if action.name.deconstantize.empty? && action.model.nil?
        model = action.model
        return ["#{action.name.deconstantize} is not a model: declare model, or move the action"] unless model.is_a?(Class) && model < ActiveRecord::Base
        problems = []
        problems << "no area maps #{model.name}: add it to the app's areas" if Actions.config.require_area && !action.area
        if action.more_than_verb? && action.declared_query.nil?
          problems << "#{action.action_words.join(" ")} says more than #{action.verb}: name the policy query, authorize :#{action.verb}? or another"
        end
        policy = action.policy_class
        if policy.nil?
          problems << "#{model.name} has no #{action.policy_label} policy"
        elsif !action.policy_rule?(action.policy_query)
          problems << "#{policy}##{action.policy_query} is missing: add it, or authorize another query"
        end
        begin
          action.writable_fields
        rescue ArgumentError => error
          problems << error.message
        end
        problems
      end

      # @param name [String]
      # @return [Class, nil]
      def self.find(name) = actions.find { |action| action.action_name == name.to_s }

      # @param name [String]
      # @return [Class]
      # @raise [Error::UnknownAction]
      def self.fetch(name) = find(name) || raise(Error::UnknownAction, name)

      # @param caller [Caller]
      # @return [Array<Class>] the actions this caller may run
      def self.runnable(caller)
        Actions.within(caller) { |fresh| actions.select { |action| action.runnable_for?(fresh) } }
      end

      # @param caller [Caller]
      # @return [Array<Hash>] visible definitions, each marked runnable or not
      #   for this caller, from one fresh check of the caller
      def self.catalogue(caller)
        Actions.within(caller) do |fresh|
          actions.select { |action| action.available_to?(fresh) }
            .map { |action| action.definition.merge("runnable" => fresh.agent_allowed?(action)) }
        end
      end

      # @return [Array<Hash>] every action's definition, as written to the catalogue file
      def self.definitions = actions.map(&:definition)

      # @return [String] hash of every definition
      def self.version = @version ||= Digest::SHA256.hexdigest(JSON.generate(definitions))[0, 16]

      # @return [Pathname] the committed catalogue, which a spec checks matches the code
      def self.catalogue_path = Rails.root.join(Actions.config.catalogue_path)

      # @return [String] the catalogue file's contents for the code as it stands
      def self.catalogue_json = "#{JSON.pretty_generate(definitions)}\n"

      def self.relative(path) = Pathname(path).relative_path_from(Rails.root).to_s
      private_class_method :relative
    end
  end
end
