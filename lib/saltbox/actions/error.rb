module Saltbox
  module Actions
    # A refusal every surface reports the same way: a code, an HTTP status and
    # a message written for a person or a model. Field errors are keyed by
    # input name. Anything else an action raises is a bug and becomes a 500.
    #
    # Each subclass sets its HTTP status and default message. Its code is its
    # class name in snake_case (Forbidden gives forbidden), unless a code is
    # passed in. A default message may name the app as %{app}.
    class Error < StandardError
      class_attribute :default_status, default: :bad_request, instance_writer: false
      class_attribute :default_message, default: "Something went wrong", instance_writer: false
      # Codes whose name differs in the :type error format (Configuration#error_format).
      TYPES = {"validation_failed" => "validation_error"}.freeze

      # @return [Hash{String=>Array<String>}, nil] field errors by input name
      attr_reader :errors
      # @return [Hash, nil] facts about the refusal a caller can act on, such as the area it needs
      attr_reader :details

      # @param message [String, nil] what went wrong and what to do
      # @param code [Symbol, String, nil] the error code callers see; the class's code when nil
      # @param status [Symbol, Integer, nil] the HTTP status; the class's default_status when nil
      # @param errors [Hash, nil] field errors keyed by input name
      # @param details [Hash, nil] facts about the refusal a caller can act on
      #
      # @example
      #   raise ApplicationAction::Error.new("Published events are locked and cannot be edited",
      #     code: :event_locked, status: :unprocessable_content)
      def initialize(message = nil, code: nil, status: nil, errors: nil, details: nil)
        @code = code&.to_s
        @status = status
        @errors = errors
        @details = details
        super(message || format(default_message, app: Actions.config.app_name))
      end

      # @return [String] this error class's default code: its name in snake_case
      def self.code = name.demodulize.underscore
      # @return [String] the error code callers see
      def code = @code || self.class.code
      # @return [Symbol, Integer] the HTTP status
      def status = @status || default_status

      # @return [String] the error's name in the :type format: its code, or validation_error for validation_failed
      def type = TYPES.fetch(code, code)

      # The body every surface sends. By default {error: {code, message,
      # errors, details}}. With Configuration#error_format :type it is
      # {error: {type, message, details}}, with the fields that have errors
      # listed in details.fields.
      #
      # @return [Hash]
      def as_json(*)
        return {"error" => {"code" => code, "message" => message, "errors" => errors, "details" => details}.compact} unless Actions.config.error_format == :type
        details = errors.present? ? (self.details || {}).stringify_keys.merge("fields" => errors.keys) : self.details
        {"error" => {"type" => type, "message" => message, "details" => details}.compact}
      end

      # No valid credential, on every surface.
      class Unauthorized < Error
        self.default_status = :unauthorized
        self.default_message = "Sign in to %{app}, or send a valid bearer token."
      end

      # The person lacks the right, on every surface.
      class Forbidden < Error
        self.default_status = :forbidden
        self.default_message = "You don't have permission to do this."

        # @param fields [Array<String>] fields the person sent but may not change
        # @return [Forbidden] naming each field
        def self.for_fields(fields) = new("You can't change #{fields.to_sentence}.", errors: fields.index_with { ["you can't change this"] })
      end

      # An agent asked for an action only a person may take.
      class HumanRequired < Error
        self.default_status = :forbidden
        self.default_message = "Only a person can do this, in %{app}."
      end

      # An agent asked for a :confirm action, Configuration#enforce_confirm is
      # on, and the app's Configuration#confirm hook did not approve it.
      class ConfirmationRequired < Error
        self.default_status = :forbidden
        self.default_message = "The person must approve this in %{app} before it runs."
      end

      # A read-only connection asked for a change, or a connection's access
      # does not reach the action.
      class InsufficientScope < Error
        self.default_status = :forbidden
        self.default_message = "This connection can only read. Reconnect and allow changes to use this action."
      end

      # Also the answer for a record the person may not see, so its existence
      # never shows.
      class NotFound < Error
        self.default_status = :not_found
        self.default_message = "Not found."
      end

      # No action has the requested name.
      class UnknownAction < Error
        self.default_status = :not_found

        # @param name [String]
        def initialize(name)
          super("No action is called #{name}. List actions at /api/v1/actions, or use find_action.")
        end
      end

      # The arguments or request body are not valid.
      class ValidationFailed < Error
        self.default_status = :unprocessable_content
        self.default_message = "The arguments are not valid."

        # A failed result object as a refusal, with the result's errors
        # joined as the message and no field errors. Raised inside a change,
        # it rolls back everything the action wrote.
        #
        # @param result [#errors] a failure, whose errors are strings
        # @return [ValidationFailed]
        def self.from_result(result) = new(Array(result.errors).join("; ").presence)

        # The refusal for an action's or a record's validation errors: the
        # full messages, in the person's language, and the errors by field,
        # without the field's name, as a record's errors.as_json gives them
        # ({"title" => ["can't be blank"]}). A screen adds them back to its
        # record with errors.add(field, message).
        #
        # @param errors [ActiveModel::Errors]
        # @param fallback [String, nil] the message when there are none to list
        # @return [ValidationFailed]
        def self.for(errors, fallback: nil)
          new(errors.full_messages.to_sentence.presence || fallback, errors: errors.to_hash.transform_keys(&:to_s).presence)
        end
      end

      # A record cannot be deleted while others depend on it (Active Record's
      # DeleteRestrictionError, from `dependent: :restrict_with_exception`).
      class InUse < Error
        self.default_status = :unprocessable_content
        self.default_message = "Something else still uses this, so it can't be deleted."
      end
    end

    # #perform never called authorize, under an adapter with no check of its own.
    class AuthorizationNotPerformedError < StandardError; end

    # #perform never called policy_scope, under an adapter with no check of its own.
    class PolicyScopingNotPerformedError < StandardError; end
  end
end
