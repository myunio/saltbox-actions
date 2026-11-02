require "json_schemer"
require "concurrent/map"

module Saltbox
  module Actions
    # Checks a caller's input against an action's JSON Schema before the
    # action runs. It refuses, naming each field:
    # - a field the schema does not list;
    # - a value of the wrong type;
    # - a missing required field.
    class Arguments
      # @param schema [Hash] a closed JSON Schema object
      # @param name [String, nil] the action's name, used in error messages
      def initialize(schema, name: nil)
        @schema = schema
        @name = name
      end

      # @param action [Class]
      # @return [Arguments] a checker for the action's input schema
      def self.for(action) = new(action.input_schema, name: action.action_name)

      # A null sent for a field that cannot be null counts as left out, since
      # agents often send null for a field they mean to skip.
      #
      # @param arguments [Hash, nil]
      # @return [Hash{String => Object}] the input with string keys, without those nulls, and each
      #   declared default for an argument left out
      # @raise [Error::Invalid] for unknown or invalid arguments
      def validate!(arguments)
        arguments = {} if arguments.nil?
        raise Error::Invalid.new("Arguments must be an object", errors: {"arguments" => ["Must be an object"]}) unless arguments.is_a?(Hash)
        properties = @schema.fetch("properties")
        arguments = arguments.deep_stringify_keys.reject { |name, value| value.nil? && properties.key?(name) && !Schema.nullable?(properties[name]) }
        # Defaults are checked as if sent, so a bad default fails here and a
        # default satisfies a required argument.
        arguments = defaults(properties).merge(arguments)
        failures = schemer.validate(arguments).to_a
        raise Error::Invalid.new(failures.pluck("error").join("; "), errors: field_errors(failures)) if failures.any?
        arguments
      end

      # @return [Concurrent::Map] compiled JSON Schema checkers, cached by schema
      def self.schemers = @schemers ||= Concurrent::Map.new

      private

      # A copy for this call: the schema is shared by every caller, and an
      # action may change a value it was given.
      def defaults(properties) = properties.filter_map { |name, schema| [name, schema["default"].deep_dup] if schema.key?("default") }.to_h

      def field_errors(failures)
        failures.each_with_object({}) do |error, result|
          names = error["data_pointer"].split("/")[1]&.then { |part| [part.gsub("~1", "/").gsub("~0", "~")] }
          names ||= error.dig("details", "missing_keys") || ["arguments"]
          names.each { |name| (result[name] ||= []) << message(name, error) }
        end
      end

      def message(name, error)
        return "#{@name} takes no id; declare argument :id" if name == "id" && @name && !@schema.fetch("properties").key?("id")
        error["error"]
      end

      def schemer
        self.class.schemers[@schema] ||= JSONSchemer.schema(@schema, regexp_resolver: "ecma")
      end
    end
  end
end
