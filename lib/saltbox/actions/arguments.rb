require "json_schemer"
require "concurrent/map"

module Saltbox
  module Actions
    # Checks a caller's input against an action's JSON Schema before the
    # action runs. It first casts what an HTML form sends, with each input's
    # Active Model type (Casting), then refuses, naming each field:
    # - a field of the action's model the caller may not set (forbidden);
    # - a field the schema does not list;
    # - a value of the wrong type, or a number its type cannot hold;
    # - a missing required field.
    # @api private
    class Arguments
      # @param schema [Hash] a closed JSON Schema object
      # @param name [String, nil] the action's name, used in error messages
      # @param types [Hash{String => Object}] what casts each input (Casting.cast)
      # @param defaults [Hash{String => Object}, nil] each input's default, a value or a callable
      #   giving it; nil for the schema's own defaults
      # @param forbidden [#call, nil] whether a name the schema does not list is a field
      #   the caller may not set, refused with Error::ForbiddenFields rather than as unknown
      def initialize(schema, name: nil, types: {}, defaults: nil, forbidden: nil)
        @schema = schema
        @name = name
        @types = types
        @defaults = defaults || schema.fetch("properties").filter_map { |field, property| [field, property["default"]] if property.key?("default") }.to_h
        @forbidden = forbidden
      end

      # @param action [Class]
      # @param caller [Caller, nil] whose schema; nil for the catalog's
      # @return [Arguments] a checker for the action's input schema for that caller,
      #   refusing a field they may not set with Error::ForbiddenFields
      def self.for(action, caller = nil)
        input = action.input(caller)
        new(input.schema, name: action.action_name, types: input.types, defaults: input.defaults, forbidden: action.method(:model_field?))
      end

      # Checks input against the action's schema for a caller, inside the
      # caller's set-up, as an invocation does; for the schema matchers.
      #
      # @param action [Class]
      # @param arguments [Hash, nil]
      # @param caller [Caller, nil] nil for the catalog's schema
      # @return [Hash] the checked input
      # @raise [Error::ValidationFailed, Error::Forbidden]
      def self.check(action, arguments, caller = nil)
        return self.for(action).validate!(arguments) unless caller
        Actions.within(caller) { |fresh| self.for(action, fresh).validate!(arguments) }
      end

      # A null sent for a field that cannot be null counts as left out, since
      # agents often send null for a field they mean to skip.
      #
      # @param arguments [Hash, nil]
      # @return [Hash{String => Object}] the input with string keys, cast, without those nulls, and each
      #   declared default for an argument left out
      # @raise [Error::ValidationFailed] for unknown or invalid arguments
      def validate!(arguments)
        arguments = {} if arguments.nil?
        raise Error::ValidationFailed.new("Arguments must be an object", errors: {"arguments" => ["Must be an object"]}) unless arguments.is_a?(Hash)
        properties = @schema.fetch("properties")
        refuse_forbidden!(arguments.keys.map(&:to_s) - properties.keys)
        arguments = arguments.deep_stringify_keys.to_h { |name, value| [name, Casting.cast(value, @types[name])] }
        arguments = arguments.reject { |name, value| value.nil? && properties.key?(name) && !Schema.nullable?(properties[name]) }
        # Defaults are checked as if sent, so a bad default fails here and a
        # default satisfies a required argument.
        arguments = defaults(properties, arguments.keys).merge(arguments)
        failures = schemer.validate(arguments).to_a
        errors = field_errors(failures)
        out_of_range = arguments.keys.select { Casting.invalid?(arguments[it], @types[it]) }
        out_of_range.each { (errors[it] ||= []) << "is out of range" }
        messages = failures.map { sentence(it) } + out_of_range.map { "value at `/#{it}` is out of range" }
        raise Error::ValidationFailed.new(messages.join("; "), errors:) if errors.any?
        Current.arguments_checked = true
        arguments
      end

      # @return [Concurrent::Map] compiled JSON Schema checkers, cached by schema
      def self.schemers = @schemers ||= Concurrent::Map.new

      private

      def refuse_forbidden!(unlisted)
        forbidden = @forbidden ? unlisted.select { @forbidden.call(it) } : []
        raise Error::ForbiddenFields.new(fields: forbidden) if forbidden.any?
      end

      # The default of each input left out, for this call: a callable's
      # value, or a copy of a literal one, since an action may change a value
      # it was given. Each is turned into JSON by its type, as a caller would
      # send it (Casting.json_value), so the schema checks it and the action
      # casts it like any other input;
      # the input checked is then the input the action runs with, which a
      # confirmation sees whole. A null for a field that cannot be null
      # counts as left out, as a sent one does.
      def defaults(properties, sent)
        @defaults.except(*sent)
          .to_h { |name, default| [name, Casting.json_value(default.respond_to?(:call) ? default.call : default, @types[name]).deep_dup] }
          .reject { |name, value| value.nil? && !Schema.nullable?(properties.fetch(name, {})) }
      end

      def field_errors(failures)
        failures.each_with_object({}) do |error, result|
          names = error["data_pointer"].split("/")[1]&.then { |part| [part.gsub("~1", "/").gsub("~0", "~")] }
          names ||= error.dig("details", "missing_keys") || ["arguments"]
          names.each { |name| (result[name] ||= []) << message(name, error) }
        end
      end

      def message(name, error)
        return "#{@name} takes no id; declare attribute :id" if name == "id" && @name && !@schema.fetch("properties").key?("id")
        return "is not an input; #{takes}" if unknown?(error)
        error["error"]
      end

      # The whole message for one failure: json_schemer's, or for a field
      # the schema does not list, which fields it does.
      def sentence(error)
        return error["error"] unless unknown?(error)
        name = error["data_pointer"].delete_prefix("/").gsub("~1", "/").gsub("~0", "~")
        "#{@name || "The action"} does not take #{name}. It #{takes}."
      end

      def unknown?(error) = error["schema_pointer"] == "/additionalProperties"

      def takes
        inputs = @schema.fetch("properties").keys
        inputs.any? ? "takes #{inputs.join(", ")}" : "takes no input"
      end

      def schemer
        self.class.schemers[@schema] ||= JSONSchemer.schema(@schema, regexp_resolver: "ecma")
      end
    end
  end
end
