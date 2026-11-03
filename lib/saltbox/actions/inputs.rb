module Saltbox
  module Actions
    # An action's input. An action is an Active Model object: its attributes
    # are its input, read as methods (`reason`, not `params[:reason]`), and
    # its validations are its checks. The JSON Schema agents read is derived
    # from them (Schema):
    # - each attribute's type gives its JSON type;
    # - `validates presence: true` makes it required;
    # - `inclusion: {in: [...]}` gives its enum;
    # - `length:` gives minLength and maxLength;
    # - `numericality:` with number bounds gives minimum and maximum.
    # Every validation runs on every call, after the schema check, and its
    # errors are refused as validation_failed, by field.
    #
    # Fields of the action's model are not attributes. A create or update
    # takes those its authorization adapter permits the caller (Schema);
    # with no adapter that supplies them, an action lists them with
    # `accepts`. Either way #perform reads them with permitted_attributes.
    #
    # @example
    #   class Payments::VoidAction < ApplicationAction
    #     attribute :reason, :string, description: "Why the payment is being voided"
    #     validates :reason, presence: true
    #   end
    # @api private
    module Inputs
      extend ActiveSupport::Concern
      include ActiveModel::API
      include ActiveModel::Attributes

      included do
        class_attribute :_declares_id, :_accepted_fields, instance_accessor: false, instance_predicate: false, default: nil
      end

      # The types an attribute takes. A time is a time of day, "HH:MM"; a hash
      # takes any keys, which the action checks itself.
      TYPES = %i[string integer decimal boolean date datetime time array hash].freeze

      # A list attribute's type: each item is cast with its own type, or, for
      # a list of records, each field with its type.
      #
      # @!attribute item [ActiveModel::Type::Value, Hash{String => ActiveModel::Type::Value}]
      # @api private
      class List < ActiveModel::Type::Value
        attr_reader :item

        # @param item [ActiveModel::Type::Value, Hash{String => ActiveModel::Type::Value}]
        def initialize(item)
          @item = item
          super()
        end

        # @return [Symbol]
        def type = :array

        private

        def cast_value(value) = value.is_a?(Array) ? value.map { cast_item(it) } : value

        def cast_item(entry)
          return @item.cast(entry) unless @item.is_a?(Hash)
          return entry unless entry.is_a?(Hash)
          entry.to_h do |name, field|
            type = @item[name.to_s]
            [name, type ? type.cast(field) : field]
          end
        end
      end

      # A date and time read in the app's time zone (Time.zone), as Active
      # Record reads a datetime column: "2026-11-02T18:30" is half past six
      # where the app is, not in UTC. A time with an offset keeps its instant.
      # @api private
      class ZonedDateTime < ActiveModel::Type::DateTime
        private

        def cast_value(value)
          super(value.respond_to?(:in_time_zone) ? value.in_time_zone : value)
        rescue ArgumentError
          nil
        end
      end

      class_methods do
        # Declares an input, as Active Model does, and adds it to the input
        # schema. `attribute :id`, with no type, declares the id of the one
        # record the action works on, for a verb outside the verb table.
        #
        # @param name [Symbol]
        # @param type [Symbol, nil] one of TYPES; :string when left out
        # @param of [Symbol, Hash, nil] for an :array, what it holds: a type, or each item's fields and their types
        # @param nullable [Boolean] whether null clears the value; otherwise null counts as left out
        # @param description [String, nil] what agents read, unless the locale file describes it
        # @param default [Object, #call, nil] the value when the caller leaves it out, listed in the
        #   schema; or a callable giving it, called once per call. Either is checked against the
        #   schema as if the caller had sent it (Arguments#validate!).
        # @return [void]
        # @raise [ArgumentError] for a type not in TYPES, or a name the action already uses,
        #   such as params, render or errors
        #
        # @example A list of records, each with typed fields
        #   attribute :payments, :array, of: {amount: :decimal, paid_on: :date}
        # @example A described input with a default
        #   attribute :status, :string, description: "Only events with this status"
        # @api public
        def attribute(name, type = nil, of: nil, nullable: false, description: nil, **options)
          name = name.to_s
          @inputs = nil
          return self._declares_id = true if name == "id" && type.nil?
          type ||= :string
          raise ArgumentError, "#{name} is a method every action has: name the attribute another way" if reserved_name?(name)
          raise ArgumentError, "#{name} takes a type: one of #{TYPES.join(", ")}" unless TYPES.include?(type)
          unknown = options.keys - [:default]
          raise ArgumentError, "#{name} takes no #{unknown.join(", ")}: validations shape an attribute's schema" if unknown.any?
          cast_type = Inputs.cast_type(type, of:)
          # The default is filled in with the input, before the schema check,
          # never by Active Model once the action is built.
          super(name, cast_type)
          declared_attributes[name] = {type:, of:, nullable:, description: description&.squish, cast_type:, **options.slice(:default)}
        end

        # @return [Hash{String => Hash}] the attributes declared with `attribute`, including the parent class's
        # @api private
        def declared_attributes
          @declared_attributes ||= (superclass.respond_to?(:declared_attributes) ? superclass.declared_attributes.dup : {})
        end

        # @return [Boolean] whether the action declares `attribute :id`
        # @api private
        def declares_id? = _declares_id || false

        # Names the model fields the action takes, for an app whose
        # authorization adapter does not say which fields a person may set.
        # They are typed from the model's columns, a belongs_to under its
        # association's name, and #perform reads the ones sent with
        # permitted_attributes. With an adapter that supplies the fields
        # (a Pundit policy, or an ActionPolicy one, with permitted_attributes),
        # the policy is the one list and `accepts` fails rails actions:check.
        #
        # @param fields [Array<Symbol>]
        # @return [Array<String>]
        # @api public
        def accepts(*fields)
          @inputs = nil
          self._accepted_fields = fields.map(&:to_s).freeze
        end

        # @return [Array<String>] the fields named with `accepts`
        # @api private
        def accepted_fields = _accepted_fields || []

        # Declares the paging inputs a list takes, as attributes the action
        # reads like any other: page, from 1, and page_size, up to
        # max_page_size. The action pages its records itself, with the app's
        # own paging library.
        #
        # @param page_size [Integer] page_size when the caller leaves it out
        # @param max_page_size [Integer] the largest page_size a caller may ask for
        # @return [void]
        #
        # @example
        #   paginated page_size: 50
        #
        #   def perform
        #     @events = policy_scope(Event).order(:starts_on).offset((page - 1) * page_size).limit(page_size)
        #     render :index
        #   end
        # @api public
        def paginated(page_size: 25, max_page_size: 100)
          attribute :page, :integer, default: 1
          attribute :page_size, :integer, default: page_size
          validates :page, numericality: {greater_than_or_equal_to: 1}
          validates :page_size, numericality: {greater_than_or_equal_to: 1, less_than_or_equal_to: max_page_size}
        end

        # Active Model's; a validation may change the schema, so it is built again.
        def validates_with(...)
          @inputs = nil
          super
        end

        private

        # A method the action's own classes define (params, render, errors,
        # authorize, id), which an attribute's reader would replace. Ruby's
        # own, such as format, an attribute may take, as a model's column may.
        def reserved_name?(name)
          return false if declared_attributes.key?(name)
          (method_defined?(name) || private_method_defined?(name)) && !Object.method_defined?(name) && !Object.private_method_defined?(name)
        end
      end

      # @param type [Symbol] one of TYPES
      # @param of [Symbol, Hash, nil] what an :array holds
      # @return [ActiveModel::Type::Value] the type that casts the attribute, once
      def self.cast_type(type, of: nil)
        case type
        when :hash then ActiveModel::Type::Value.new
        when :array then List.new(of.is_a?(Hash) ? of.to_h { |name, item| [name.to_s, cast_type(item)] } : cast_type(of || :string))
        # An integer input is stored nowhere, so it may be as large as a bigint.
        when :integer then ActiveModel::Type.lookup(:integer, limit: 8)
        when :datetime then ZonedDateTime.new
        else ActiveModel::Type.lookup(type)
        end
      end
    end
  end
end
