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
        integer: {"type" => "integer"}, decimal: {"type" => "number"}, float: {"type" => "number"},
        boolean: {"type" => "boolean"}, date: {"type" => "string", "format" => "date"}, time: TIME,
        datetime: {"type" => "string", "format" => "date-time"}
      }.freeze
      # A decimal argument also takes a string, since a JSON number can lose
      # digits of a large amount and a string keeps every one. A hash takes any
      # keys: the action checks them itself.
      ARGUMENT_TYPES = COLUMN_TYPES.slice(:string, :integer, :boolean, :date, :time)
        .merge(decimal: {"type" => %w[number string]}, array: {"type" => "array"}, hash: {"type" => "object"}).freeze
      # The schema of the id input that names the record an action works on.
      ID = {"type" => "string"}.freeze

      # One permitted field, under the name callers send: event_type for the
      # event_type_id column.
      #
      # @!attribute key [String] the policy's key, which is what the model receives
      # @!attribute schema [Hash] the field's JSON Schema
      # @!attribute required [Boolean] whether a create must send it
      # @!attribute reference [Class, nil] the model a foreign key points to
      Field = Data.define(:key, :schema, :required, :reference)

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

      class_methods do
        # @return [Hash] the action's input schema: the same for every caller,
        #   and refusing any field it does not list
        def input_schema
          @input_schema ||= begin
            properties = {}
            required = []
            properties["id"] = ID if takes_id? && !arguments.key?("id")
            required << "id" if properties.key?("id")
            writable_fields.each do |name, field|
              properties[name] = field.schema
              required << name if field.required && verb == "create"
            end
            arguments.each do |name, argument|
              properties[name] = argument[:schema]
              required << name if argument[:required]
            end
            properties = properties.to_h { |name, schema| [name, schema.merge("description" => field_description(name) || schema["description"]).compact] }
            {"type" => "object", "properties" => properties, "required" => required.uniq, "additionalProperties" => false}.freeze
          end
        end

        # Checks a caller's input before the action runs. Override it in the
        # app's base class to check input another way.
        #
        # @param arguments [Hash, nil]
        # @param _caller [Caller]
        # @return [Hash] the input #perform receives as params
        # @raise [Error::Invalid]
        def validate_arguments(arguments, _caller) = Arguments.for(self).validate!(arguments)

        # @return [Boolean] whether the verb takes the fields the policy permits
        def writes_fields? = !declared_name && WRITING_VERBS.include?(verb)

        # The fields the model's policy permits for a new record, asked of the
        # schema principal (Configuration#schema_principal), so every caller
        # gets the same schema. Permitting#permitted_attributes checks the real
        # person again on each call.
        #
        # @return [Hash{String => Field}] keyed by the name callers send
        # @raise [ArgumentError] for a permitted name that is not a column, an association or an argument
        def writable_fields
          return {} unless writes_fields? && model
          @writable_fields ||= policy_keys.each_with_object({}) do |key, fields|
            next if arguments.key?(key)
            name, field = column_field(key)
            raise ArgumentError, "#{policy_class}#permitted_attributes lists #{key}, which is not a column, an association or an argument of #{self.name}" unless field
            fields[name] = field
          end
        end

        # @return [Array<String>] the keys the policy permits for the schema principal
        def policy_keys
          principal = Actions.config.schema_principal
          ask = ->(user) { permitted_attribute_names_for(user, model.new) }
          principal ? principal.call(ask) : ask.call(nil)
        end

        private

        def column_field(key)
          association = model.reflect_on_association(key.delete_suffix("_id")) if key.end_with?("_id")
          column = model.columns_hash[key]
          return unless column
          required = !column.null && column.default.nil? && column.default_function.nil?
          if association&.belongs_to?
            schema = {"type" => "string"}
            return [association.name.to_s, Field.new(key:, schema: column.null ? Schema.nullable(schema) : schema, required:, reference: association.klass)]
          end
          schema = if (values = model.defined_enums[key])
            {"type" => "string", "enum" => values.keys}
          else
            COLUMN_TYPES.fetch(model.type_for_attribute(key).type) { return }.dup
          end
          schema["maxLength"] = column.limit if column.type == :string && column.limit
          [key, Field.new(key:, schema: column.null ? Schema.nullable(schema) : schema, required:, reference: nil)]
        end
      end
    end
  end
end
