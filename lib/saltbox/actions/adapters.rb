module Saltbox
  module Actions
    # The optional parts of the gem. Each lives under adapters/, grouped by
    # its job, and loads only when the app declares it in its configure
    # block; everything outside adapters/ is core and always loads.
    #
    #   Saltbox::Actions.configure do |config|
    #     config.adapters = [:pundit, :controller, :mcp, :paper_trail]
    #   end
    #
    # A declaration is checked as it is made, at boot: an unknown name, two
    # authorization adapters, or an adapter whose gem is not in the bundle
    # is refused, naming the fix. A declared authorization adapter is
    # included in Base, so every action inherits it, and an action not
    # authorized by it is refused when it is run. Naming an adapter the app did not declare
    # raises NotDeclared, naming the line to add.
    #
    # The order of config.adapters does not matter: what each adapter does
    # around a call runs in one fixed order, declared once in Base
    # (Callbacks), and the rest answers a question only when asked.
    #
    # The test helpers are not declared: a spec or test helper requires
    # them, as pundit/rspec is required (see TESTING).
    module Adapters
      # One optional adapter. Its name is its file's, under
      # adapters/<group>/; its constant is in the group's module.
      #
      # @!attribute name [Symbol] what config.adapters lists, the file's name: :mcp
      # @!attribute group [Symbol] the folder and module it is in: :entry_points
      # @!attribute constant [String] its constant in the group: "MCP"
      # @!attribute gem [String, nil] the gem it needs, beyond Rails
      # @!attribute summary [String] what it does, in one line
      # @!attribute load_on [Symbol, nil] the framework load hook it waits for, so
      #   declaring it does not load that framework during boot
      Adapter = Data.define(:name, :group, :constant, :gem, :summary, :load_on) do
        # @return [String] the file to require
        def path = "saltbox/actions/adapters/#{group}/#{name}"

        # @return [String] its full constant name
        def constant_name = "Saltbox::Actions::Adapters::#{group.to_s.camelize}::#{constant}"
      end

      # Every adapter, in the order the install generator lists them.
      LIST = [
        Adapter.new(:pundit, :authorization, "Pundit", "pundit",
          "authorizes each action with the model's Pundit policy", nil),
        Adapter.new(:action_policy, :authorization, "ActionPolicy", "action_policy",
          "authorizes each action with the model's ActionPolicy policy", nil),
        Adapter.new(:controller, :entry_points, "Controller", nil,
          "serves every action as a JSON API, from one controller that includes it", nil),
        Adapter.new(:mcp, :entry_points, "MCP", "mcp",
          "serves every action to AI agents over the Model Context Protocol", nil),
        Adapter.new(:ruby_llm_tool, :entry_points, "RubyLLMTool", "ruby_llm",
          "gives an in-app RubyLLM chat the actions as tools", nil),
        Adapter.new(:invocation_job, :entry_points, "InvocationJob", nil,
          "runs an action later as an Active Job, for perform_later", :active_job),
        Adapter.new(:acts_as_tenant, :tenancy, "ActsAsTenant", "acts_as_tenant",
          "runs every call in the caller's tenant with acts_as_tenant, and refuses a person with none", nil),
        Adapter.new(:flipper, :features, "Flipper", "flipper",
          "asks Flipper whether an action's feature is on, for the tenant or the person", nil),
        Adapter.new(:paper_trail, :audit, "PaperTrail", "paper_trail",
          "stamps each PaperTrail version an action writes with the person, and notes it as a change", nil),
        Adapter.new(:pagy, :lists, "Pagy", "pagy",
          "pages lists with Pagy, and is the list adapter unless the app names its own", nil),
        Adapter.new(:approvals, :confirmation, "Approvals", nil,
          "keeps each agent's :confirm call for the person to approve, in saltbox_action_approvals (rails g actions:approvals)", :active_record)
      ].index_by(&:name).freeze

      # For each load hook an adapter may wait for, the framework's file and
      # the class whose loading runs the hook.
      # @api private
      FRAMEWORKS = {active_job: ["active_job", "ActiveJob::Base"], active_record: ["active_record", "ActiveRecord::Base"]}.freeze

      # The test helpers, each required from the app's own helper file.
      TESTING = {
        "RSpec" => 'require "saltbox/actions/adapters/testing/rspec" in spec/rails_helper.rb',
        "Minitest" => 'require "saltbox/actions/adapters/testing/minitest" in test/test_helper.rb'
      }.freeze

      # Raised when code names an adapter the app did not declare.
      class NotDeclared < NameError; end

      # Raised at boot when a declared adapter's gem is not in the bundle.
      class MissingGem < LoadError; end

      class << self
        # Checks a declaration and loads each adapter in it. Called by
        # Configuration#adapters=.
        #
        # @param names [Array<Symbol, String>]
        # @return [Array<Symbol>] the declared names, frozen
        # @raise [ArgumentError] for an unknown name, or two authorization adapters
        # @raise [MissingGem] naming the gem to add
        # @api private
        def declare(names)
          names = Array(names).map(&:to_sym).uniq
          unknown = names - LIST.keys
          if unknown.any?
            raise ArgumentError, "config.adapters: #{unknown.map(&:inspect).join(", ")} is not an adapter. " \
              "The adapters are #{LIST.keys.map(&:inspect).join(", ")}"
          end
          authorization = names.select { LIST.fetch(it).group == :authorization }
          if authorization.size > 1
            raise ArgumentError, "config.adapters declares #{authorization.map(&:inspect).join(" and ")}: " \
              "an app authorizes its actions with one; keep one"
          end
          names.each { load(LIST.fetch(it)) }
          names.freeze
        end

        # @param name [Symbol]
        # @return [Boolean] whether the app declared it
        def declared?(name) = Actions.config.adapters.include?(name)

        # @return [Module, nil] the declared authorization adapter, which
        #   Base includes (see .authorize_base!)
        def authorization
          adapter = Actions.config.adapters.map { LIST.fetch(it) }.find { it.group == :authorization }
          adapter && constant(adapter)
        end

        # Includes the declared authorization adapter in the gem's own Base,
        # so every action inherits it: the app's base class and any other,
        # defined before the declaration or after, and again on each reload.
        # Called when the app's configuration declares its adapters.
        #
        # @return [void]
        # @raise [ArgumentError] when Base already includes another authorization adapter
        # @api private
        def authorize_base!
          adapter = authorization or return
          installed = authorization_modules.find { Base.include?(it) }
          if installed && installed != adapter
            raise ArgumentError, "config.adapters declares #{adapter.name}, but Base already authorizes with #{installed.name}: " \
              "an app declares its authorization adapter once, in config/initializers/saltbox_actions.rb; restart to change it"
          end
          Base.include(adapter)
        end

        # Refuses to run an action whose authorization is not the declared
        # adapter's, so a declared adapter is never silently skipped. Run by
        # Invocation before anything else.
        #
        # @param action [Class]
        # @return [void]
        # @raise [ArgumentError] naming the fix
        # @api private
        def check_authorization!(action)
          adapter = authorization or return
          in_effect = action.ancestors.find { it == Actions::Authorization::None || authorization_modules.include?(it) }
          return if in_effect == adapter
          raise ArgumentError, "#{action.name || action} is not authorized by #{adapter.name}, which config.adapters declares, " \
            "but by #{in_effect&.name || "nothing"}: refused. Remove the include from the action or its base class"
        end

        # What a declared adapter does once the app has loaded: PaperTrail
        # starts noting versions. Run by the Railtie after initialization.
        #
        # @return [void]
        # @api private
        def install!
          Audit::PaperTrail.install! if declared?(:paper_trail)
          Confirmation::Approvals.install! if declared?(:approvals)
        end

        # A group module's const_missing: loads a declared adapter that
        # waits for its framework, and names the line to add for one the
        # app did not declare.
        #
        # @param group [Module]
        # @param name [Symbol]
        # @return [Module] the adapter
        # @raise [NotDeclared]
        # @api private
        def missing(group, name)
          adapter = LIST.values.find { "#{it.group.to_s.camelize}::#{it.constant}" == "#{group.name.demodulize}::#{name}" }
          return unless adapter
          return constant(adapter) if declared?(adapter.name)
          raise NotDeclared.new("#{adapter.constant_name} is an optional adapter the app has not declared: " \
            "add :#{adapter.name} to config.adapters in config/initializers/saltbox_actions.rb", name)
        end

        private

        # The authorization adapters loaded so far.
        def authorization_modules
          LIST.each_value.select { it.group == :authorization && Authorization.const_defined?(it.constant, false) }
            .map { Authorization.const_get(it.constant, false) }
        end

        def load(adapter)
          require_gem(adapter) if adapter.gem
          if adapter.load_on
            ActiveSupport.on_load(adapter.load_on) { require adapter.path }
          else
            require adapter.path
          end
        end

        def require_gem(adapter)
          require adapter.gem
        rescue LoadError => error
          raise unless error.path == adapter.gem
          raise MissingGem, "config.adapters declares :#{adapter.name}, which needs the #{adapter.gem} gem: " \
            "add gem \"#{adapter.gem}\" to the Gemfile"
        end

        # Loads the framework an adapter waits for, whose load hook then
        # requires the adapter, and answers the adapter's constant.
        def constant(adapter)
          if adapter.load_on
            file, base = FRAMEWORKS.fetch(adapter.load_on)
            require file
            base.constantize
          end
          require adapter.path
          adapter.constant_name.constantize
        end
      end

      # Entry points: the ways into the app beside its own screens.
      module EntryPoints
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # The authorization libraries an action may be checked with.
      module Authorization
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # The tenant every call runs in.
      module Tenancy
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # Feature flags an action's `feature` is checked with.
      module Features
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # Audit trails that stamp and note what a change wrote.
      module Audit
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # Paging libraries lists page with.
      module Lists
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # Ways a person approves what their agents ask to do.
      module Confirmation
        def self.const_missing(name) = Adapters.missing(self, name) || super
      end

      # The test helpers, required from the app's spec or test helper.
      module Testing
        def self.const_missing(name)
          line = TESTING[name.to_s] or return super
          raise NotDeclared.new("#{self.name}::#{name} is loaded by the app's test setup: #{line}", name)
        end
      end
    end
  end
end
