require "concurrent/map"

module Saltbox
  module Actions
    # Builds the JSON Schema of an action's input. Agents read it before they
    # call, and the CLI turns it into flags.
    # - A create or update takes the fields its model's policy permits, typed
    #   from the model's columns.
    # - Any other input is declared with `argument`.
    # Descriptions come from config/locales/actions.en.yml.
    module Schema
      extend ActiveSupport::Concern

      # Verbs whose actions take the fields the model's policy permits.
      WRITING_VERBS = %w[create update].freeze
      TIME = {"type" => "string", "pattern" => "^\\d{2}:\\d{2}$"}.freeze
      COLUMN_TYPES = {
        string: {"type" => "string"}, text: {"type" => "string"}, uuid: {"type" => "string", "format" => "uuid"},
        integer: {"type" => "integer"}, decimal: {"type" => %w[number string], "pattern" => "^[+-]?(\\d+\\.?\\d*|\\.\\d+)$"},
        float: {"type" => "number"},
        boolean: {"type" => "boolean"}, date: {"type" => "string", "format" => "date"}, time: TIME,
        datetime: {"type" => "string", "format" => "date-time"}
      }.freeze
      # A decimal also takes a string of digits, since a JSON number can lose
      # digits of a large amount and a string keeps every one. A hash takes any
      # keys: the action checks them itself.
      ARGUMENT_TYPES = COLUMN_TYPES.slice(:string, :integer, :decimal, :boolean, :date, :time)
        .merge(array: {"type" => "array"}, hash: {"type" => "object"}).freeze
      # The schema of a record's id: the id input, or a foreign key sent under
      # its association's name. Rails code passes integer ids, and an id may
      # also be a uuid or another string.
      ID = {"type" => %w[string integer]}.freeze

      # One permitted field, under the name callers send: event_type for the
      # event_type_id column.
      #
      # @!attribute key [String] the policy's key, which is what the model receives
      # @!attribute schema [Hash] the field's JSON Schema
      # @!attribute required [Boolean] whether a create must send it
      # @!attribute reference [Class, nil] the model a foreign key points to
      # @!attribute type [ActiveModel::Type::Value] the column's type, which casts what a form sends
      Field = Data.define(:key, :schema, :required, :reference, :type)

      # @param type [Symbol]
      # @param nullable [Boolean]
      # @param enum [Array, nil]
      # @param of [Symbol, Hash, nil] what an array holds
      # @return [Hash] the JSON Schema for an `argument` declaration
      def self.for_argument(type, nullable:, enum:, of: nil)
        schema = ARGUMENT_TYPES.fetch(type).dup
        # JSON has no symbols, so symbol values are listed as strings. Numbers
        # and booleans stay as they are.
        schema["enum"] = enum.map { it.is_a?(Symbol) ? it.to_s : it } if enum
        if type == :array
          schema["items"] = of.is_a?(Hash) ? item_object(of) : ARGUMENT_TYPES.fetch(of || :string)
          schema["maxItems"] = Actions.config.max_array_items
        end
        nullable ? nullable(schema) : schema
      end

      # @param type [Symbol]
      # @param of [Symbol, Hash, nil] what an array holds
      # @return [ActiveModel::Type::Value, Array, Hash, nil] what casts an `argument`'s input (Casting.cast)
      def self.type_for_argument(type, of: nil)
        case type
        when :hash then nil
        when :array then [of.is_a?(Hash) ? of.to_h { |name, item| [name.to_s, type_for_argument(item)] } : type_for_argument(of || :string)]
        # An integer argument is stored nowhere, so it may be as large as a bigint.
        when :integer then ActiveModel::Type.lookup(:integer, limit: 8)
        else ActiveModel::Type.lookup(type)
        end
      end

      # The schema of one item in a list of records. Fields other than those
      # listed are refused. Each field may also be null, which a form sends for
      # a field it leaves empty.
      #
      # @param fields [Hash{Symbol => Symbol}] each field's name and type
      # @return [Hash]
      def self.item_object(fields)
        {"type" => "object", "properties" => fields.to_h { |name, type| [name.to_s, nullable(ARGUMENT_TYPES.fetch(type))] },
         "additionalProperties" => false}
      end

      # @param schema [Hash]
      # @return [Hash] the schema with null allowed; an enum lists null too,
      #   since JSON Schema checks enum separately from type
      def self.nullable(schema)
        schema = schema.merge("type" => [*schema["type"], "null"])
        schema["enum"] = [*schema["enum"], nil] if schema.key?("enum")
        schema
      end

      # @param schema [Hash]
      # @return [Boolean] whether the schema allows null
      def self.nullable?(schema) = Array(schema["type"]).include?("null")

      # What one caller may send to an action, built the first time a caller
      # with the same permitted fields asks for it.
      #
      # @!attribute schema [Hash] the JSON Schema, refusing any field it does not list
      # @!attribute types [Hash{String => ActiveModel::Type::Value, Array, Hash}] what casts each
      #   input before the schema checks it (Casting.cast)
      # @!attribute fields [Hash{String => Field}] the model fields among them, keyed by the name callers send
      Input = Data.define(:schema, :types, :fields)

      class_methods do
        # The input schema for one caller. A create or update lists the
        # fields the model's policy permits that caller, so two callers see
        # different schemas when their policy permits different fields.
        # Without a caller it is the catalogue's schema, built for
        # Configuration#schema_principal.
        #
        # @param caller [Caller, nil]
        # @return [Hash]
        def input_schema(caller = nil) = input(caller).schema

        # @param caller [Caller, nil]
        # @return [Hash{String => Field}] the policy's permitted fields for the caller, keyed by the name callers send
        # @raise [ArgumentError] for a permitted name that is not a column, an association or an argument
        def writable_fields(caller = nil) = input(caller).fields

        # Asks the policy which fields the caller may set, on a new record,
        # each time; the Input is built once per action, per list of fields
        # and per locale, then shared by every caller with the same list, so
        # one caller's fields never reach another's schema. Run it inside the
        # caller's Configuration#around_invocation, where the policy's tenant
        # is set: every surface does. Permitting#permitted_attributes checks
        # the fields against the real record again.
        #
        # @param caller [Caller, nil] nil for the catalogue's schema (Configuration#schema_principal)
        # @return [Input]
        def input(caller = nil)
          keys = (writes_fields? && model) ? permitted_keys(caller) : []
          input_for(keys)
        end

        # @return [Input] the action's input without the policy's fields:
        #   its id and declared arguments, the same for every caller
        def declared_input = input_for([])

        # Checks a caller's input before the action runs. Override it in the
        # app's base class to check input another way.
        #
        # @param arguments [Hash, nil]
        # @param caller [Caller]
        # @return [Hash] the input #perform receives as params
        # @raise [Error::Invalid]
        # @raise [Error::Forbidden] naming each field of the model the caller may not set
        def validate_arguments(arguments, caller) = Arguments.for(self, caller).validate!(arguments)

        # @return [Boolean] whether the verb takes the fields the policy permits
        def writes_fields? = !declared_name && WRITING_VERBS.include?(verb)

        # @param name [String, Symbol]
        # @return [Boolean] whether some caller may send it: an argument, the
        #   id, or for a create or update a column or association of the model
        def declares_input?(name)
          name = name.to_s
          arguments.key?(name) || (name == "id" && takes_id?) || model_field?(name)
        end

        # @param name [String]
        # @return [Boolean] whether a create or update could take it, for a
        #   caller whose policy permits it: a column, or a belongs_to under
        #   its association's name. Not the primary key.
        def model_field?(name)
          return false unless writes_fields? && model && name != model.primary_key
          model.columns_hash.key?(name) || !!model.reflect_on_association(name)&.belongs_to?
        end

        private

        # @return [Array<String>] the keys the policy permits the caller, or
        #   the schema principal without one
        def permitted_keys(caller)
          return policy_keys(caller.account) if caller
          principal = Actions.config.schema_principal
          principal ? principal.call(->(account) { policy_keys(account) }) : policy_keys(nil)
        end

        def policy_keys(account) = permitted_attribute_names_for(account, model.new).uniq.freeze

        def input_for(keys)
          (@inputs ||= Concurrent::Map.new).compute_if_absent([keys, I18n.locale]) { build_input(keys) }
        end

        def build_input(keys)
          fields = keys.each_with_object({}) do |key, result|
            next if arguments.key?(key)
            name, field = column_field(key)
            raise ArgumentError, "#{policy_class ? "#{policy_class}#permitted_attributes" : "permitted_attribute_names_for"} lists #{key}, which is not a column, an association or an argument of #{self.name}" unless field
            result[name] = field
          end
          properties = {}
          required = []
          properties["id"] = ID if takes_id? && !arguments.key?("id")
          required << "id" if properties.key?("id")
          fields.each do |name, field|
            properties[name] = field.schema
            required << name if field.required && verb == "create"
          end
          arguments.each do |name, argument|
            properties[name] = argument[:schema]
            required << name if argument[:required]
          end
          properties = properties.to_h { |name, schema| [name, schema.merge("description" => field_description(name) || schema["description"]).compact] }
          schema = {"type" => "object", "properties" => properties, "required" => required.uniq, "additionalProperties" => false}.freeze
          types = fields.transform_values(&:type).merge(arguments.transform_values { it[:type] }).compact.freeze
          Input.new(schema:, types:, fields: fields.freeze)
        end

        def column_field(key)
          association = model.reflect_on_association(key.delete_suffix("_id")) if key.end_with?("_id")
          column = model.columns_hash[key]
          return unless column
          required = !column.null && column.default.nil? && column.default_function.nil?
          type = model.type_for_attribute(key)
          if association&.belongs_to?
            return [association.name.to_s, Field.new(key:, schema: column.null ? Schema.nullable(ID) : ID, required:, reference: association.klass, type:)]
          end
          schema = if (values = model.defined_enums[key])
            {"type" => "string", "enum" => values.keys}
          else
            COLUMN_TYPES.fetch(type.type) { return }.dup
          end
          schema["maxLength"] = column.limit if column.type == :string && column.limit
          [key, Field.new(key:, schema: column.null ? Schema.nullable(schema) : schema, required:, reference: nil, type:)]
        end
      end
    end
  end
end
