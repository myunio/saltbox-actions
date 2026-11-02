module Saltbox
  module Actions
    # An action written as an Active Model object: a command. It runs through
    # the same Invocation as an action (refusals, authorization, confirmation,
    # summaries, transactions, MCP, the API and the assistant), so commands
    # and actions work side by side in one app.
    #
    # What differs from an action:
    # - It lives in app/commands, named after its resource's controller:
    #   Events::UpdateCommand works on Event (the namespace, singular) and is
    #   update_event, as Event::UpdateAction is.
    # - Its input is Active Model attributes, read as methods (reason, not
    #   params[:reason]). The JSON Schema agents read is derived from each
    #   attribute's type and its validations: presence makes it required,
    #   inclusion gives its enum.
    # - `accepts` names the model fields a create or update takes; each call
    #   checks them against the person's policy, and `accepted_attributes`
    #   returns the ones sent.
    # - A member command (one whose verb works on one record) reads its record
    #   with a method named after its model (event, payment): found through
    #   the person's policy scope, authorized with the command's rule, and set
    #   as the view's @event. A command whose lookup differs defines
    #   find_<model>(scope).
    # - `agents` says who besides the person may run it, defaulting by kind:
    #   :allowed for a read or a change, :confirm for a destructive command.
    # - Verbs beyond the gem's table are declared once in the app's base
    #   class, with `verb`.
    # - perform_now and perform_later run it by class, as a job does.
    #
    # @example
    #   class ApplicationCommand < Saltbox::Actions::Command
    #     include Saltbox::Actions::Authorization::Pundit
    #     abstract!
    #     verb :void, kind: :destructive, on: :member
    #   end
    #
    #   class Events::UpdateCommand < ApplicationCommand
    #     accepts :title, :starts_on
    #
    #     def perform
    #       event.update!(accepted_attributes)
    #       render :show
    #     end
    #   end
    class Command < Base
      include ActiveModel::Validations
      include ActiveModel::Attributes

      # The gem's verbs, with the two a command repeats without changing
      # anything more: update and delete.
      VERBS = Naming::VERBS.to_h do |verb, rule|
        [verb, rule.merge(idempotent: %w[update delete].include?(verb))]
      end.freeze
      # Instance variables Active Model keeps for itself; views never see them.
      MODEL_IVARS = %w[attributes errors validation_context context_for_validation].freeze

      class_attribute :verb_table, instance_accessor: false, default: VERBS

      class << self
        # Marks a base class that is not itself a command, such as
        # ApplicationCommand, as ActionController::Base does.
        #
        # @return [void]
        def abstract! = @abstract = true

        # @return [Boolean]
        def abstract? = @abstract == true

        # Called with no verb, the command's own verb: the first word of its
        # class name. Called with verbs, declares them for every command
        # below this class, the way an app adds inflections.
        #
        # @param verbs [Array<Symbol>]
        # @param kind [Symbol] :read, :change or :destructive
        # @param on [Symbol] :member for a verb that works on one record named by an id, or :collection
        # @param idempotent [Boolean] whether running it again changes nothing more
        # @return [String, Hash]
        #
        # @example
        #   verb :cancel, :reinstate, kind: :change, on: :member, idempotent: true
        def verb(*verbs, kind: nil, on: :collection, idempotent: false)
          return super() if verbs.empty?
          raise ArgumentError, "verb #{verbs.join(", ")} needs kind: :read, :change or :destructive" unless Naming::KINDS.include?(kind)
          raise ArgumentError, "on: is :member or :collection, not #{on.inspect}" unless %i[member collection].include?(on)
          self.verb_table = verb_table.merge(verbs.to_h { [it.to_s, {kind:, id: on == :member, idempotent:}] }).freeze
        end

        # @return [Array<String>] the words before Command: ["show", "history"] for Events::ShowHistoryCommand
        def action_words = name.demodulize.delete_suffix("Command").underscore.split("_")

        # @return [Class, nil] the model: the namespace, singular (Events gives Event), unless declared
        def model(value = nil)
          return @model = value if value
          return @model if declared_name
          @model || name.deconstantize.presence&.singularize&.safe_constantize
        end

        def table_verb? = verb_table.key?(verb)

        def kind(value = nil)
          return super if value
          declared_name ? declared_kind : (verb_table.dig(verb, :kind) || declared_kind)
        end

        def takes_id? = (!declared_name && verb_table.dig(verb, :id) == true) || arguments.key?("id")

        def idempotent? = super || (!declared_name && verb_table.dig(verb, :idempotent) == true)

        # Who besides the person on the app's screens may run it; see
        # Declarations#connections. Left out, it follows the kind: :confirm
        # for a destructive command, :allowed otherwise.
        #
        # @param rule [Symbol, nil] :allowed, :confirm or :never
        # @return [Symbol]
        def agents(rule = nil) = connections(rule)

        def connections(rule = nil)
          return super if rule
          super() || ((kind == :destructive) ? :confirm : :allowed)
        end

        # Declares the policy rule the command asks, when its verb's is not right.
        #
        # @param rule [Symbol]
        # @return [Symbol]
        def policy_rule(rule) = authorize(rule)

        # Declares an input, as Active Model does, and adds it to the input
        # schema. Its validations shape the schema too (see validates_with).
        #
        # @param name [Symbol]
        # @param type [Symbol] one of Declarations::TYPES
        # @param description [String, nil] what agents read, in place of the locale file's
        # @param options [Hash] Active Model's, such as default:
        # @return [void]
        def attribute(name, type = :string, description: nil, **options)
          super(name, type, **options)
          command_attributes[name.to_s] = {type:, description:, default: options[:default]}
          declare_argument(name.to_s)
        end

        # @return [Hash{String => Hash}] each attribute declared with `attribute`, with its type
        def command_attributes = @command_attributes ||= (superclass.respond_to?(:command_attributes) ? superclass.command_attributes.dup : {})

        # Active Model's, then each attribute it names gets its schema again,
        # so `validates :reason, presence: true` makes reason required.
        def validates_with(*args, &block)
          super
          options = args.extract_options!
          Array(options[:attributes]).map(&:to_s).select { command_attributes.key?(it) }.each { declare_argument(it) }
        end

        # Names the model fields the command takes, as a create or update
        # action takes those its policy permits: typed from the model's
        # columns, a belongs_to under its association's name. Each call
        # checks the fields sent against the person's policy, refusing one
        # they may not change by name.
        #
        # @param fields [Array<Symbol>]
        # @return [Array<String>]
        def accepts(*fields) = @accepted = fields.map(&:to_s).freeze

        # @return [Array<String>] the fields declared with `accepts`
        def accepted = @accepted || []

        def writes_fields? = !declared_name && accepted.any?

        # @return [String] the command's key in the locale file, under commands: events.update
        def locale_key = name.underscore.delete_suffix("_command").tr("/", ".")

        def locale_scope = "commands"

        # A field's description: the command's own in the locale file, then
        # the resource's (commands.events.fields), then the attribute's
        # description:, then the shared one (actions.shared.fields).
        def field_description(field)
          resource = locale_key.rpartition(".").first.presence
          keys = [:"commands.#{locale_key}.fields.#{field}"]
          keys << :"commands.#{resource}.fields.#{field}" if resource
          keys << :"actions.shared.fields.#{field}" unless command_attributes.dig(field.to_s, :description)
          I18n.t(keys.shift, default: [*keys, ""]).squish.presence
        end

        # Lists the command as an MCP tool of its own; see Declarations#mcp_core.
        #
        # @return [void]
        def featured = mcp_core

        # Runs the command now, through the same path every surface uses.
        #
        # @param caller [Caller]
        # @param arguments [Hash]
        # @return [Result]
        # @raise [Error]
        def perform_now(caller:, **arguments) = Invocation.call(name: self, caller:, arguments:)

        # Runs the command later, as an Active Job, as the same caller. The
        # refusals run again then, so a person who lost access in between is
        # refused; a refusal is logged and dropped, never retried.
        #
        # @param caller [Caller]
        # @param arguments [Hash]
        # @return [ActiveJob::Base, false]
        def perform_later(caller:, **arguments)
          CommandJob.perform_later(name, arguments.deep_stringify_keys, CommandJob.serialize_caller(caller))
        end

        # @return [String, nil] the name of the method that reads a member command's record: event, payment
        def record_reader = (model.model_name.singular if takes_id? && model)

        private

        def permitted_keys(_caller)
          accepted.map do |field|
            association = model.reflect_on_association(field)
            association&.belongs_to? ? association.foreign_key.to_s : field
          end
        end

        def declare_argument(name)
          attribute = command_attributes.fetch(name)
          required = validators_on(name).any? { it.kind == :presence && !it.options.key?(:if) && !it.options.key?(:unless) }
          inclusion = validators_on(name).find { it.kind == :inclusion && it.options[:in].is_a?(Array) }
          argument(name, attribute[:type], required:, enum: inclusion&.options&.fetch(:in), description: attribute[:description],
            **attribute.slice(:default).compact)
        end
      end

      abstract!

      # Active Model's initialize takes a hash of attributes; a command's
      # input comes checked, as the action's params, so Base's runs instead.
      def initialize(actor:, params:)
        @attributes = self.class._default_attributes.deep_dup
        Base.instance_method(:initialize).bind_call(self, actor:, params:)
        self.class.command_attributes.each_key { public_send(:"#{it}=", params[it]) if params.key?(it) }
        define_record_reader
      end

      # @return [Object] the person the command acts for
      def current_user = account

      # @return [Caller] who is calling, and from where
      def current_caller = actor

      # @return [Object] the id the caller sent, for a member command
      def id = params[:id]

      # Checks the command's own validations, then runs it.
      #
      # @return [Result]
      # @raise [Error::Invalid] naming each field that fails
      def perform_now
        unless valid?
          raise Error::Invalid.new(errors.full_messages.to_sentence, errors: errors.to_hash(true).transform_keys(&:to_s))
        end
        super
      end

      # The model fields the caller sent that the command accepts, checked
      # against the person's policy for the record (or the model, for a
      # create), each reference looked up through their scope.
      #
      # @return [ActiveSupport::HashWithIndifferentAccess]
      def accepted_attributes = permitted_attributes(self.class.record_reader ? command_record : self.class.model)

      private

      # The member command's record: found through the person's policy scope,
      # with find_<model>(scope) when the command defines it, authorized, and
      # set as the view's instance variable (@event).
      def command_record
        return @_record if defined?(@_record)
        reader = self.class.record_reader
        scope = policy_scope(self.class.model)
        finder = :"find_#{reader}"
        record = respond_to?(finder, true) ? send(finder, scope) : scope.find(id)
        authorize(record)
        instance_variable_set(:"@#{reader}", record)
        @_record = record
      end

      def define_record_reader
        reader = self.class.record_reader
        return if reader.nil? || respond_to?(reader, true)
        self.class.send(:define_method, reader) { command_record }
      end

      def view_assigns = super.except(*MODEL_IVARS)
    end
  end
end
