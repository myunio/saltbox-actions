require "concurrent/map"

module Saltbox
  module Actions
    # Builds the JSON Schema of an action's input. Agents read it before they
    # call, and the CLI turns it into flags.
    # - Model fields, typed from the model's columns: for a create or update,
    #   the ones the authorization adapter permits the caller; with no
    #   adapter that supplies them, the ones named with `accepts`.
    # - Every other input is an attribute (Inputs), shaped by its validations.
    # Descriptions come from config/locales/actions.en.yml, or the class.
    # @api private
    module Schema
      extend ActiveSupport::Concern

      # Verbs whose actions take the fields the authorization adapter permits.
      WRITING_VERBS = %w[create update].freeze
      # A time of day, "HH:MM" from 00:00 to 23:59: Active Record turns 24:00
      # into the next day and 99:99 into nil, so neither is taken.
      TIME = {"type" => "string", "pattern" => "^([01]\\d|2[0-3]):[0-5]\\d$"}.freeze
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
      ATTRIBUTE_TYPES = COLUMN_TYPES.slice(:string, :integer, :decimal, :boolean, :date, :datetime, :time)
        .merge(array: {"type" => "array"}, hash: {"type" => "object"}).freeze
      # Numericality options with a number, and the JSON Schema keyword each gives.
      NUMBER_BOUNDS = {greater_than_or_equal_to: "minimum", less_than_or_equal_to: "maximum",
                       greater_than: "exclusiveMinimum", less_than: "exclusiveMaximum"}.freeze
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
      # @api private
      Field = Data.define(:key, :schema, :required, :reference, :type)

      # @param type [Symbol]
      # @param nullable [Boolean]
      # @param enum [Array, nil]
      # @param of [Symbol, Hash, nil] what an array holds
      # @return [Hash] the JSON Schema of an attribute's type
      def self.for_attribute(type, nullable:, enum:, of: nil)
        schema = ATTRIBUTE_TYPES.fetch(type).dup
        # JSON has no symbols, so symbol values are listed as strings. Numbers
        # and booleans stay as they are.
        schema["enum"] = enum.map { it.is_a?(Symbol) ? it.to_s : it } if enum
        if type == :array
          schema["items"] = of.is_a?(Hash) ? item_object(of) : ATTRIBUTE_TYPES.fetch(of || :string)
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
        {"type" => "object", "properties" => fields.to_h { |name, type| [name.to_s, nullable(ATTRIBUTE_TYPES.fetch(type))] },
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
      # @!attribute defaults [Hash{String => Object}] each attribute's default, a value or a callable
      #   giving it, which Arguments fills in for an input left out
      # @api private
      Input = Data.define(:schema, :types, :fields, :defaults)

      class_methods do
        # The input schema for one caller. A create or update lists the
        # fields the authorization adapter permits that caller, so two callers
        # see different schemas when their policy permits different fields.
        # Without a caller it is the catalog's schema, built for
        # Configuration#schema_user.
        #
        # @param caller [Caller, nil]
        # @return [Hash]
        # @api public
        def input_schema(caller = nil) = input(caller).schema

        # @param caller [Caller, nil]
        # @return [Hash{String => Field}] the model fields the caller may send, keyed by the name callers send
        # @raise [ArgumentError] for a permitted name that is not a column, an association or an attribute
        # @api private
        def writable_fields(caller = nil) = input(caller).fields

        # Asks the adapter which fields the caller may set, on a new record,
        # each time; the Input is built once per action, per list of fields
        # and per locale, then shared by every caller with the same list, so
        # one caller's fields never reach another's schema. Run it inside the
        # caller's Configuration#around_invocation, where the policy's tenant
        # is set: every surface does. Permitting#permitted_attributes checks
        # the fields against the real record again.
        #
        # @param caller [Caller, nil] nil for the catalog's schema (Configuration#schema_user)
        # @return [Input]
        # @api private
        def input(caller = nil)
          keys = writes_fields? ? permitted_keys(caller) : []
          input_for(keys)
        end

        # @return [Input] the action's input without the adapter's fields:
        #   its id, its attributes and any fields it accepts, the same for every caller
        # @api private
        def declared_input = input_for(accepted_fields.any? ? permitted_keys(nil) : [])

        # Checks a caller's input before the action runs. Override it in the
        # app's base class to check input another way.
        #
        # @param arguments [Hash, nil]
        # @param caller [Caller]
        # @return [Hash] the input the action is built from
        # @raise [Error::ValidationFailed]
        # @raise [Error::Forbidden] naming each field of the model the caller may not set
        # @api public
        def validate_arguments(arguments, caller) = Arguments.for(self, caller).validate!(arguments)

        # @return [Boolean] whether the action takes model fields: the ones it accepts, or for a
        #   create or update, the ones its authorization adapter supplies
        # @api private
        def writes_fields?
          return false unless model.is_a?(Class) && model < ActiveRecord::Base
          accepted_fields.any? || (!declared_name && WRITING_VERBS.include?(verb) && supplies_fields?)
        end

        # @param name [String, Symbol]
        # @return [Boolean] whether some caller may send it: an attribute, the
        #   id, or a model field the action takes
        # @api private
        def declares_input?(name)
          name = name.to_s
          declared_attributes.key?(name) || (name == "id" && takes_id?) || model_field?(name)
        end

        # @param name [String]
        # @return [Boolean] whether the action could take it as a model field,
        #   for a caller whose policy permits it: one it accepts, or else a
        #   column, or a belongs_to under its association's name. Not the primary key.
        # @api private
        def model_field?(name)
          return false unless writes_fields? && name != model.primary_key
          return accepted_fields.include?(name) if accepted_fields.any?
          model.columns_hash.key?(name) || !!model.reflect_on_association(name)&.belongs_to?
        end

        private

        # @return [Array<String>] the keys the action accepts; otherwise the
        #   ones the policy permits the caller, or the schema user without one
        # @api private
        def permitted_keys(caller)
          return accepted_keys if accepted_fields.any?
          return policy_keys(caller.user) if caller
          schema_user = Actions.config.schema_user
          schema_user ? schema_user.call(->(user) { policy_keys(user) }) : policy_keys(nil)
        end

        # The fields named with `accepts`, keyed as the model takes them: a
        # belongs_to by its foreign key.
        def accepted_keys
          accepted_fields.map do |field|
            association = model.reflect_on_association(field)
            association&.belongs_to? ? association.foreign_key.to_s : field
          end.freeze
        end

        def policy_keys(user) = permitted_attribute_names_for(user, model.new).uniq.freeze

        def input_for(keys)
          (@inputs ||= Concurrent::Map.new).compute_if_absent([keys, I18n.locale]) { build_input(keys) }
        end

        def build_input(keys)
          fields = keys.each_with_object({}) do |key, result|
            next if declared_attributes.key?(key)
            name, field = column_field(key)
            raise ArgumentError, "#{fields_source} lists #{key}, which is not a column, an association or an attribute of #{self.name}" unless field
            result[name] = field
          end
          properties = {}
          required = []
          properties["id"] = ID if takes_id?
          required << "id" if takes_id?
          fields.each do |name, field|
            properties[name] = field.schema
            required << name if field.required && verb == "create"
          end
          declared_attributes.each do |name, attribute|
            properties[name] = attribute_schema(name, attribute)
            required << name if required_attribute?(name)
          end
          properties = properties.to_h { |name, schema| [name, schema.merge("description" => field_description(name)).compact] }
          schema = {"type" => "object", "properties" => properties, "required" => required.uniq, "additionalProperties" => false}.freeze
          types = fields.transform_values(&:type).merge(declared_attributes.transform_values { it[:cast_type] }).freeze
          defaults = declared_attributes.filter_map { |name, attribute| [name, attribute[:default]] if attribute.key?(:default) }.to_h.freeze
          Input.new(schema:, types:, fields: fields.freeze, defaults:)
        end

        def fields_source
          return "accepts" if accepted_fields.any?
          policy_class ? "#{policy_class}#permitted_attributes" : "permitted_attribute_names_for"
        end

        # The validations that always run shape the schema; one with if:,
        # unless: or on: runs only sometimes, so it is left to run.
        def schema_validators(name)
          validators_on(name).reject { |validator| validator.options.key?(:if) || validator.options.key?(:unless) || validator.options.key?(:on) }
        end

        # A callable default's value is not in the schema, so an agent cannot
        # tell it may leave the attribute out: such an attribute is not
        # required. Its presence validation still runs on the default.
        def required_attribute?(name)
          return false if declared_attributes.dig(name, :default).respond_to?(:call)
          schema_validators(name).any? { it.kind == :presence && !it.options[:allow_nil] && !it.options[:allow_blank] }
        end

        def attribute_schema(name, attribute)
          validators = schema_validators(name)
          inclusion = validators.find { it.kind == :inclusion && it.options[:in].is_a?(Array) }
          # allow_blank lets a form's empty choice ("") through, so the schema lists it too.
          enum = inclusion && (inclusion.options[:in] + (inclusion.options[:allow_blank] ? [""] : [])).uniq
          schema = Schema.for_attribute(attribute[:type], nullable: attribute[:nullable], enum:, of: attribute[:of])
          validators.each do |validator|
            case validator.kind
            when :length
              keys = (attribute[:type] == :array) ? %w[minItems maxItems] : %w[minLength maxLength]
              low, high = validator.options.values_at(:minimum, :maximum).map { validator.options[:is] || it }
              schema[keys.first] = low if low.is_a?(Integer)
              schema[keys.last] = high if high.is_a?(Integer)
            when :numericality
              NUMBER_BOUNDS.each { |option, keyword| schema[keyword] = validator.options[option] if validator.options[option].is_a?(Numeric) }
            end
          end
          default = attribute[:default]
          schema["default"] = default.as_json if attribute.key?(:default) && !default.respond_to?(:call)
          schema.compact
        end

        def column_field(key)
          column = model.columns_hash[key]
          return unless column
          association = belongs_to_for(key)
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

        # The belongs_to whose foreign key the column is, as Active Record
        # reflects it: account for organization_id, under
        # `belongs_to :account, foreign_key: :organization_id`. A foreign key
        # whose record no one scope can check is refused, so it never passes
        # as a plain value.
        #
        # @return [ActiveRecord::Reflection::BelongsToReflection, nil]
        # @raise [ArgumentError] for a key two associations share, a polymorphic one or part of a composite one
        def belongs_to_for(key)
          matches = model.reflect_on_all_associations(:belongs_to).select { Array(it.foreign_key).map(&:to_s).include?(key) }
          return if matches.empty?
          fix = "a reference field cannot check the record sent, so leave #{key} out of #{fields_source} and take the record in an attribute"
          raise ArgumentError, "#{model.name}##{key} is the foreign key of #{matches.map(&:name).to_sentence}: #{fix}" if matches.size > 1
          association = matches.first
          raise ArgumentError, "#{model.name}##{key} is the foreign key of #{association.name}, which is polymorphic: #{fix}" if association.polymorphic?
          raise ArgumentError, "#{model.name}##{key} is part of #{association.name}'s composite foreign key: #{fix}" if association.foreign_key.is_a?(Array)
          association
        end
      end
    end
  end
end
