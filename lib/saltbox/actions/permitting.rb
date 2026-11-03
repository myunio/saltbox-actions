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
    # refused field is answered by Configuration#on_forbidden_fields.
    module Permitting
      # @param record [ActiveRecord::Base, Class] the record, or its model for a create
      # @return [ActiveSupport::HashWithIndifferentAccess] the fields sent, keyed as the policy names them
      # @raise [ArgumentError] in an action that takes no model fields
      # @raise [Error::Forbidden] naming each field the person may not change
      # @raise [Error::Invalid] for a reference to a record the person cannot pick
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

      # The id of the record a field names, looked up through the person's
      # policy scope.
      #
      # @param model [Class<ActiveRecord::Base>]
      # @param value [String] the id sent
      # @param field [String] the name it was sent under
      # @return [Object] the record's id
      # @raise [Error::Invalid] when the person cannot see such a record
      def resolve_reference(model, value, field:)
        id = model.type_for_attribute(model.primary_key).cast(value)
        found = scoped_records(model).find_by(model.primary_key => id) if id
        return found.id if found
        raise Error::Invalid.new("#{field.humanize} isn't a #{model.model_name.human.downcase} you can see",
          errors: {field => ["isn't a #{model.model_name.human.downcase} you can see"]})
      end

      # @param fields [Array<String>] the fields sent that the person may not change
      # @raise [Error::Forbidden] the one Configuration#on_forbidden_fields returns
      def refuse_forbidden_fields!(fields)
        raise Actions.config.on_forbidden_fields.call(current_caller, self.class, fields)
      end
    end
  end
end
