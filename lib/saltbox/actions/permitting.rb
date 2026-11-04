module Saltbox
  module Actions
    # Does the job of Pundit's permitted_attributes for an action's model
    # fields, which have already passed the action's JSON Schema. The fields
    # allowed are the ones the authorization adapter permits the person on
    # the record, or the ones the action accepts (Inputs#accepts). It differs
    # from Pundit's in three ways:
    # - a field the person may not change is refused by name, not silently
    #   dropped;
    # - a foreign key is sent under its association's name (event_type, not
    #   event_type_id) and is looked up before it is saved;
    # - values are passed on exactly as sent (a time stays its "HH:MM"
    #   string), so Active Record parses them itself, in the app's time zone.
    #
    # The app's base class may override #resolve_reference to say more. A
    # refused field raises Error::ForbiddenFields, which the app may rescue.
    # @api private
    module Permitting
      # @param record [ActiveRecord::Base, Class] the record, or its model for a create
      # @return [ActiveSupport::HashWithIndifferentAccess] the fields sent, keyed as the policy names them
      # @raise [ArgumentError] in an action that takes no model fields
      # @raise [Error::ForbiddenFields] naming each field the person may not change
      # @raise [Error::ValidationFailed] for a reference to a record the person cannot pick
      # @api public
      def permitted_attributes(record)
        unless self.class.writes_fields?
          raise ArgumentError, "#{self.class.name} takes no model fields: a create or update takes the ones its policy permits, any other action names them with accepts"
        end
        allowed = self.class.accepted_fields.any? ? self.class.writable_fields.values.map(&:key) : permitted_attribute_names(record)
        sent = self.class.writable_fields(current_caller).select { |name, _| params.key?(name) }
        forbidden = sent.reject { |_, field| allowed.include?(field.key) }.keys
        refuse_forbidden_fields!(forbidden) if forbidden.any?
        sent.to_h do |name, field|
          value = params[name]
          [field.key, (field.reference && !value.nil?) ? resolve_reference(field.reference, value, field: name) : value]
        end.with_indifferent_access
      end

      private

      # The id of the record a field names.
      # - An entry in a lookup list (Configuration#lookup_lists), such as an
      #   event type, may be named by id or by its name, ignoring case and
      #   the spaces around it. Anyone who may pick from the list sees all
      #   of it, so the lookup skips the policy scope. An unknown name is
      #   refused with the names that would work, worded by the app's
      #   actions.errors.not_in_lookup_list (default "isn't one of the
      #   %{plural}"); one that matches more than one entry, with each match.
      # - Any other record is named by id, through the person's policy scope.
      #
      # @param model [Class<ActiveRecord::Base>]
      # @param value [String, nil] the id sent, or a lookup entry's name
      # @param field [String] the name it was sent under
      # @return [Object, nil] the record's id, or nil when the value is nil
      # @raise [Error::ValidationFailed] when there is no such record the person can see
      # @api public
      def resolve_reference(model, value, field:)
        return nil if value.nil?
        lookup = Actions.config.lookup_lists.include?(model.name)
        records = lookup ? model.all : scoped_records(model)
        id = model.type_for_attribute(model.primary_key).cast(value)
        found = records.find_by(model.primary_key => id) if id
        found ||= lookup_by_name(records, value, field:) if lookup
        return found.id if found
        plural = model.model_name.human.pluralize.downcase
        unknown = I18n.t("actions.errors.not_in_lookup_list", plural:, default: "isn't one of the %{plural}")
        refuse_reference!(field, unknown, "must be one of: #{records.order(:name).pluck(:name).join(", ")}") if lookup
        refuse_reference!(field, "isn't a #{model.model_name.human.downcase} you can see")
      end

      # A lookup list's entry by its full name, ignoring case and the spaces around it.
      def lookup_by_name(records, value, field:)
        matches = records.where(records.arel_table[:name].lower.eq(value.to_s.strip.downcase)).to_a
        return matches.first if matches.size <= 1
        refuse_reference!(field, "matches more than one: #{matches.map { "#{it.name} (#{it.id})" }.join(", ")}")
      end

      def refuse_reference!(field, message, detail = message)
        raise Error::ValidationFailed.new("#{field.humanize} #{message}", errors: {field => [detail]})
      end

      # @param fields [Array<String>] the fields sent that the person may not change
      # @raise [Error::ForbiddenFields]
      def refuse_forbidden_fields!(fields) = raise(Error::ForbiddenFields.new(fields:))
    end
  end
end
