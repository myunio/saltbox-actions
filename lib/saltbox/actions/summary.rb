module Saltbox
  module Actions
    # The few fields that let an agent pick a record before it asks for the
    # rest with the model's show action. A list action sends agents each
    # record's summary in place of its view, and the CLI prints the same
    # fields as its table's columns. Declared with `summary` (Declarations).
    #
    # @!attribute fields [Hash{String => #call, nil}] each field's name, and
    #   the lambda that computes it, or nil for the record's own method
    Summary = Data.define(:fields) do
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
      def call(record) = fields.to_h { |name, value| [name, (value ? value.call(record) : record.public_send(name)).as_json] }
    end
  end
end
