module Saltbox
  module Actions
    # An action's response: an HTTP status and the JSON body its view
    # rendered, or no body, and any meta beside it (pagination, counts).
    # Each surface passes it on in its own form: the API as the HTTP
    # response, MCP and assistants as the tool result, the CLI as printed
    # output.
    Result = Data.define(:status, :body, :meta, :empty) do
      # @param status [Integer]
      # @param body [Object, nil] any JSON value, false and null included
      # @param meta [Hash, nil]
      # @param empty [Boolean] whether there is no body at all (head), as against a null one
      def initialize(status:, body:, meta: nil, empty: false) = super

      # @return [Result] a 204 with no body, for an action that rendered nothing
      def self.no_content = new(status: 204, body: nil, empty: true)

      # @return [Boolean] whether the response has no body
      def empty? = empty

      # The body, so a Result renders as its body. With
      # Configuration#result_format :envelope it is {data:, meta:}, without
      # meta when there is none.
      #
      # @return [Hash, nil]
      def as_json(*)
        return body unless Actions.config.result_format == :envelope
        {"data" => body.as_json, "meta" => meta&.as_json}.compact
      end
    end
  end
end
