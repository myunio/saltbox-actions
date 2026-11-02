module Saltbox
  module Actions
    # Loads every action under the actions folder and checks it, in two
    # steps. Each error names the action and the fix.
    # - When an eager-loading app boots (production, CI), what each action
    #   declares: a setting the class name cannot give, and the class does
    #   not declare, stops the boot instead of being guessed. These checks
    #   never touch the database.
    # - `rails actions:check` (.check!), run in CI and by the registry spec,
    #   checks the rest against the models, policies and database: the
    #   policy rules, the fields each schema takes, the summaries, and the
    #   app's own checks.
    module Registry
      # @return [Array<Class>] every action, sorted by name
      def self.actions
        @actions ||= begin
          entries = Actions.config.every_file_an_action ? action_files.map { |path| action_at(path) } : descendants
          validate!(entries)
          warn_outside(entries)
          entries.sort_by(&:action_name).freeze
        end
      end

      # @return [void] forgets the loaded actions, so the next call loads them again
      def self.reset! = @actions = @version = nil

      # @return [Array<Pathname>] the folders actions load from (see Configuration#action_paths),
      #   each once however it was spelled
      def self.roots = Actions.config.action_paths.map(&:root).uniq

      # The files in the action folders, without the base class's own file
      # and folder (application_action.rb and application_action/), which hold
      # shared code. An engine's own base class, such as
      # billing/application_action.rb, is shared code too.
      #
      # @return [Array<String>] action file paths
      # @raise [ArgumentError] for a file in an action folder that is not an action
      def self.action_files
        support = "/#{Actions.config.base_class.underscore}/"
        files = roots.flat_map do |root|
          Dir[root.join("**/*.rb").to_s].reject do |path|
            "/#{Pathname(path).relative_path_from(root).to_s.delete_suffix(".rb")}/".include?(support)
          end
        end
        # A folder inside another lists its files twice: each counts once.
        files = files.uniq
        misnamed = files.reject { it.end_with?("_action.rb") }
        raise ArgumentError, "Every file in #{Actions.config.action_paths} ends _action.rb: rename or move #{misnamed.map { relative(it) }.join(", ")}" if misnamed.any?
        files
      end

      # For an app whose action folders hold other files too
      # (Configuration#every_file_an_action off): the base class's named
      # subclasses defined in those folders, once they are loaded.
      #
      # @return [Array<Class>]
      def self.descendants
        roots.select(&:directory?).each { Rails.autoloaders.main.eager_load_dir(it.to_s) }
        paths = Actions.config.action_paths
        named = named_descendants
        named.select { |action| paths.for(source(action)) }.reject { |action| named.any? { it < action } }
      end

      # The base class's subclasses that hold a name now: not anonymous
      # classes, nor ones a code reload replaced.
      #
      # @return [Array<Class>]
      def self.named_descendants
        Actions.config.base.descendants.select { |action| action.name&.safe_constantize.equal?(action) }
      end

      # Warns about the base class's subclasses that are loaded but outside
      # every action folder, such as an engine's actions before the engine
      # adds its folder: they would be missing from the API and MCP with no
      # other sign. A class other actions inherit from is a base, not an action.
      #
      # @param entries [Array<Class>]
      # @return [void]
      def self.warn_outside(entries)
        paths = Actions.config.action_paths
        named = named_descendants
        strays = (named - entries).reject { |action| named.any? { it < action } || paths.for(source(action)) }
        return if strays.empty?
        one = strays.size == 1
        warn "saltbox-actions: #{strays.map(&:name).sort.join(", ")} #{one ? "inherits" : "inherit"} from " \
          "#{Actions.config.base_class} but #{one ? "is" : "are"} outside the action folders (#{paths}), so no caller " \
          "can run #{one ? "it" : "them"}. Move #{one ? "it" : "them"}, or add the folder in an initializer: " \
          "Saltbox::Actions.config.action_paths.add(root.join(\"app/actions\"))"
      end

      # @param action [Class]
      # @return [String, nil] the file that defines it
      def self.source(action) = Object.const_source_location(action.name)&.first

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

      # The boot checks: what each action declares, and that names are
      # unique. Nothing here touches the database.
      #
      # @param entries [Array<Class>]
      # @return [void]
      # @raise [ArgumentError] naming every problem with each action
      def self.validate!(entries)
        # Each action's own checks come first: a name the others need, such
        # as a model's, may be the problem.
        problems = entries.flat_map { |action| problems(action, declared_only: true).map { "#{action.name}: #{it}" } }
        raise ArgumentError, problems.join("\n") if problems.any?
        unique!(entries, "Action names", "declare action_name on one, or give one engine's action path a namespace") { [it.action_name] }
        unique!(entries, "CLI commands", "declare cli on one, or give one engine's action path a namespace") do |action|
          [action.cli_command, *action.declared_cli&.fetch(:aliases)].map { it.join(" ") }
        end
      end

      # Every check, as `rails actions:check` runs it: the boot checks, then
      # each action's model, policy, fields and summary, and the app's own
      # checks (Configuration#action_checks and #registry_checks). It reads
      # the models' columns, so it needs the database; a write action's
      # schema is built for Configuration#schema_principal.
      #
      # @return [Array<Class>] every action, once all pass
      # @raise [ArgumentError] naming every problem with each action
      def self.check!
        entries = actions
        problems = entries.flat_map { |action| problems(action).map { "#{action.name}: #{it}" } }
        raise ArgumentError, problems.join("\n") if problems.any?
        Actions.config.registry_checks.each { it.call(entries) }
        entries
      end

      # @param entries [Array<Class>]
      # @param what [String] what must be unique, for the message
      # @param fix [String]
      # @yieldparam action [Class]
      # @yieldreturn [Array<String>] the names the action answers to
      # @raise [ArgumentError] naming each name more than one action answers to, and those actions
      def self.unique!(entries, what, fix)
        owners = entries.flat_map { |action| yield(action).uniq.map { [it, action] } }.group_by(&:first)
        clashes = owners.filter_map { |name, pairs| "#{name} (#{pairs.map { it.last.name }.sort.join(", ")})" if pairs.size > 1 }
        raise ArgumentError, "#{what} must be unique: #{clashes.join("; ")}. To fix: #{fix}" if clashes.any?
      end

      # @param action [Class]
      # @param declared_only [Boolean] only the boot checks of what the class declares
      # @return [Array<String>] what is wrong with the action, and the fix
      def self.problems(action, declared_only: false)
        return named_problems(action, declared_only:) if action.declared_name
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
        # Its name comes from its model, so this one is a boot check too.
        unmodelled = not_a_model(action)
        problems << unmodelled if unmodelled
        return problems if declared_only
        problems.concat(model_problems(action)) unless unmodelled
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
      # its kind, and its model is checked only when it declares one.
      #
      # @param action [Class]
      # @param declared_only [Boolean]
      # @return [Array<String>]
      def self.named_problems(action, declared_only: false)
        problems = []
        problems << "declare kind :read, :change or :destructive" unless action.declared_kind
        problems.concat(connection_problems(action))
        return problems if declared_only
        problems.concat(model_problems(action)) if action.model
        problems.concat(Actions.config.action_checks.flat_map { Array(it.call(action)) })
      end

      # @param action [Class]
      # @return [String, nil] for an action under a namespace that is not a model, and no model declared, the fix
      def self.not_a_model(action)
        model = action.model
        return if (action.name.deconstantize.empty? && model.nil?) || (model.is_a?(Class) && model < ActiveRecord::Base)
        "#{action.name.deconstantize} is not a model: declare model, or move the action"
      end

      # @param action [Class]
      # @return [Array<String>] what is wrong with the action's model, its
      #   authorization (see Authorization#authorization_problems) and fields, and the fix
      def self.model_problems(action)
        return [] if action.name.deconstantize.empty? && action.model.nil?
        model = action.model
        return ["#{action.name.deconstantize} is not a model: declare model, or move the action"] unless model.is_a?(Class) && model < ActiveRecord::Base
        problems = []
        problems << "no area maps #{model.name}: add it to the app's areas" if Actions.config.require_area && !action.area
        authorization = action.authorization_problems
        problems.concat(authorization)
        # The fields and summary are read from the table, which a database
        # not yet migrated lacks: that is the one fix to name.
        return problems << "#{model.name}'s table #{model.table_name} does not exist: run bin/rails db:prepare first" unless model.table_exists?
        problems.concat(schema_problems(action)) if authorization.empty?
        problems.concat(summary_problems(action))
      end

      # Builds the catalogue's input schema, which asks the policy's
      # permitted_attributes of the schema principal.
      #
      # @param action [Class] an action with a model
      # @return [Array<String>] what stops its schema being built, and the fix
      def self.schema_problems(action)
        action.input_schema
        []
      rescue ArgumentError => error
        [error.message]
      rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::NoDatabaseError
        raise
      rescue => error
        ["building its input schema asked #{action.policy_class ? "#{action.policy_class}#permitted_attributes" : "permitted_attribute_names_for"}, which raised #{error.class}: #{error.message}. " \
          "If the policy needs a person or a tenant, set config.schema_principal, which actions:check and the catalogue build schemas for"]
      end

      # @param action [Class] an action with a model
      # @return [Array<String>] what is wrong with its summary, and the fix
      def self.summary_problems(action)
        summary = action.summary
        return [] unless summary
        model = action.model
        problems = summary.fields.filter_map do |name, computed|
          "#{model.name} has no #{name} for its summary: name an attribute or method, or compute it" unless computed || model.attribute_names.include?(name) || model.method_defined?(name)
        end
        problems << "its summary leaves out id, which agents need to call show: add :id" if action.summarizes_list? && !summary.names.include?("id")
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
      # @return [Array<Hash>] visible definitions, each marked runnable or not
      #   for this caller, from one fresh check of the caller
      def self.catalogue(caller)
        Actions.within(caller) do |fresh|
          actions.select { |action| action.available_to?(fresh) }
            .map { |action| action.definition(fresh).merge("runnable" => fresh.agent_allowed?(action)) }
        end
      end

      # @return [Array<Hash>] every action's definition, as written to the catalogue file:
      #   a create or update lists the fields the policy permits Configuration#schema_principal
      def self.definitions = actions.map(&:definition)

      # The version of the actions' code, for the API's meta and the MCP
      # server: a hash of every definition without the policy's fields, so
      # no caller is needed. A caller's own fields change their catalogue's
      # ETag instead.
      #
      # @return [String]
      def self.version
        @version ||= Digest::SHA256.hexdigest(JSON.generate(actions.map { it.definition(input: it.declared_input) }))[0, 16]
      end

      # @return [Pathname] the committed catalogue, which a spec checks matches the code
      def self.catalogue_path = Rails.root.join(Actions.config.catalogue_path)

      # @return [String] the catalogue file's contents for the code as it stands
      def self.catalogue_json = "#{JSON.pretty_generate(definitions)}\n"

      def self.relative(path) = Pathname(path).relative_path_from(Rails.root).to_s
      private_class_method :relative, :named_descendants, :warn_outside, :unique!
    end
  end
end
