module Saltbox
  module Actions
    # Turns the strings an HTML form sends into the JSON values an action's
    # schema checks, with the Active Model type of each input, as Active
    # Record does when it is given params:
    # - an empty field ("") becomes what the type makes of it: nil for a
    #   number, date, boolean or enum column, and "" for a string;
    # - "12" becomes 12 for an integer, and "1.5" 1.5 for a float;
    # - "1", "true" and "on" become true for a boolean, and "0", "false" and
    #   "off" false;
    # - a form's local date-time, "2026-11-02T10:30", becomes a time in the
    #   app's time zone, keeping any fraction of a second.
    # A decimal keeps its string, so no digit is lost. Any other value stays
    # as it was sent, so the schema refuses it by name: unlike Active Record,
    # "lots" never becomes 0, "yes" never becomes true, and 30 February never
    # becomes 2 March. Casting.invalid? then finds the numbers the schema
    # passes but the type cannot hold.
    # @api private
    module Casting
      # Integer() and Float() also read 1_000, and Float() reads hex such as
      # 0x1A; a form sends neither, so both stay as sent.
      NOT_DECIMAL = /[_xX]/
      BOOLEANS = %w[1 0 t f T F true false TRUE FALSE on off ON OFF].freeze
      LOCAL_TIME = /\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?\z/

      # @param value [Object] one input as sent
      # @param type [ActiveModel::Type::Value, Inputs::List, Hash, nil] the input's type;
      #   {field => type} for a record in a list, nil to leave it as sent
      # @return [Object] the value the schema checks
      def self.cast(value, type)
        case type
        when nil then value
        when Inputs::List then value.is_a?(Array) ? cast_list(value, type.item) : value
        when Hash then value.is_a?(Hash) ? value.to_h { |name, item| [name, cast(item, type[name.to_s])] } : value
        else value.is_a?(String) ? cast_string(value, type) : value
        end
      end

      # A form's list of checkboxes or a multiple select sends a blank first
      # item so that an empty list still arrives. Rails drops it, and so does
      # this, for any list of things other than strings.
      def self.cast_list(values, type)
        values = values.map { cast(it, type) }
        (type.is_a?(ActiveModel::Type::Value) && type.cast("").nil?) ? values.compact : values
      end

      def self.cast_string(value, type)
        return type.cast(value) if value.empty?
        case type.type
        when :integer then decimal(Integer(value, 10, exception: false), value)
        when :float then decimal(Float(value, exception: false), value)
        when :boolean then BOOLEANS.include?(value) ? type.cast(value) : value
        when :datetime then local_time(value, type)
        else value
        end
      end

      # @return [Numeric, String] the number read, or the value as sent
      def self.decimal(number, value) = (number.nil? || value.match?(NOT_DECIMAL)) ? value : number

      # @return [String] an ISO 8601 time with its offset, as the schema takes,
      #   or the value as sent when it is not a real local date and time
      def self.local_time(value, type)
        year, month, day, hour, minute, second, fraction = value.match(LOCAL_TIME)&.captures
        return value unless year && Date.valid_date?(year.to_i, month.to_i, day.to_i) &&
          hour.to_i < 24 && minute.to_i < 60 && second.to_i < 60
        type.cast(value)&.iso8601([fraction.to_s.length, type.precision || 6].min) || value
      end

      # A Ruby value, such as a default, as a caller would send it for its
      # type, so the schema checks it and the action casts it back to the
      # same value: a time of day as "HH:MM", a date as "2026-11-03", and a
      # date and time in the app's time zone to the microsecond. as_json
      # alone would send a time of day as a whole timestamp, and a date and
      # time to the millisecond.
      #
      # @param value [Object]
      # @param type [ActiveModel::Type::Value, Inputs::List, Hash, nil] as for Casting.cast
      # @return [Object] a JSON value
      def self.json_value(value, type)
        case type
        when Inputs::List then value.is_a?(Array) ? value.map { json_value(it, type.item) } : value.as_json
        when Hash then value.is_a?(Hash) ? value.to_h { |name, item| [name.to_s, json_value(item, type[name.to_s])] } : value.as_json
        when ActiveModel::Type::Value then (value.is_a?(String) || value.nil?) ? value : temporal_json(value, type) || value.as_json
        else value.as_json
        end
      end

      def self.temporal_json(value, type)
        case type.type
        when :time then value.strftime("%H:%M") if value.respond_to?(:strftime)
        when :date then value.to_date.iso8601 if value.respond_to?(:to_date)
        when :datetime then value.in_time_zone.iso8601(type.precision || 6) if value.respond_to?(:in_time_zone)
        end
      end

      # @param value [Object] one input, after Casting.cast
      # @param type [ActiveModel::Type::Value, Inputs::List, Hash, nil]
      # @return [Boolean] whether it holds an integer the type cannot store, or
      #   a float that is not finite, which JSON cannot carry
      def self.invalid?(value, type)
        case value
        when Array then type.is_a?(Inputs::List) && value.any? { invalid?(it, type.item) }
        when Hash then type.is_a?(Hash) && value.any? { |name, item| invalid?(item, type[name.to_s]) }
        when Integer then type.is_a?(ActiveModel::Type::Value) && type.type == :integer && !type.serializable?(value)
        when Float then !value.finite?
        else false
        end
      end

      private_class_method :cast_list, :cast_string, :decimal, :local_time, :temporal_json
    end
  end
end
