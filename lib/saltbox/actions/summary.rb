module Saltbox
  module Actions
    # The few fields that let an agent pick a record before it asks for the
    # rest with the model's show action. A list action sends agents each
    # record's summary in place of its view, and the CLI prints the same
    # fields as its table's columns. Declared with `summary` (Declarations).
    #
    # Each field holds one plain value: its JSON is text, a number, true or
    # false, or null (a date, time or decimal is sent as text). A record, a
    # hash or a list is refused, so no attribute the summary does not name
    # reaches an agent inside another.
    #
    # @!attribute fields [Hash{String => #call, nil}] each field's name, and
    #   the lambda that computes it, or nil for the record's own method
    class Summary < Data.define(:fields)
      # The JSON a field's value may become.
      PLAIN = [String, Integer, Float, TrueClass, FalseClass, NilClass].freeze
      # The JSON Schema of a plain value, for a field not typed from a column.
      PLAIN_SCHEMA = {"type" => %w[string number boolean null]}.freeze

      # @param plain [Array<Symbol>] the record's own attributes or methods
      # @param computed [Hash{Symbol => #call}] fields computed from the record
      # @return [Summary]
      # @raise [ArgumentError] when it names no field, or a computed field is not callable
      def self.build(plain, computed)
        raise ArgumentError, "summary needs a field" if plain.empty? && computed.empty?
        computed.each do |name, value|
          raise ArgumentError, "summary #{name} is a lambda taking the record, not #{value.inspect}" unless value.respond_to?(:call)
        end
        new(fields: plain.to_h { [it.to_s, nil] }.merge(computed.transform_keys(&:to_s)).freeze)
      end

      # @return [Array<String>] the field names, in order
      def names = fields.keys

      # @param record [Object]
      # @return [Hash{String => Object}] the record's summary, as JSON
      # @raise [ArgumentError] for a field whose value is not plain
      def call(record)
        fields.to_h do |name, computed|
          value = computed ? computed.call(record) : record.public_send(name)
          json = value.as_json
          unless PLAIN.any? { json.is_a?(it) }
            raise ArgumentError, "summary #{name} is a #{value.class}: a summary field holds text, a number, true or false, a date or time, or nil"
          end
          [name, json]
        end
      end
    end
  end
end
