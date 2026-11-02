module Saltbox
  module Actions
    # The input a caller sent, already cast (Casting) and checked against the
    # action's JSON Schema. Values are JSON values: strings, numbers, booleans
    # or nil.
    # Reading a key the action does not declare raises ArgumentError instead
    # of returning nil, so a typo fails in the action's spec rather than in
    # production.
    class Params < ActiveSupport::HashWithIndifferentAccess
      # @param values [Hash]
      # @param action [Class, nil]
      def initialize(values = {}, action: nil)
        @action = action
        super(values)
      end

      # @param key [String, Symbol]
      # @return [Object, nil] the value sent, or nil when the caller left it out
      # @raise [ArgumentError] when the action declares no such input
      def [](key)
        declared!(key)
        super
      end

      # @param key [String, Symbol]
      # @return [Object]
      # @raise [ArgumentError] when the action declares no such input
      def fetch(key, ...)
        declared!(key)
        super
      end

      private

      def declared!(key)
        return unless @action
        return if @action.declares_input?(key)
        hint = (key.to_s == "id") ? "argument :id" : "it"
        raise ArgumentError, "#{@action.action_name} reads params[:#{key}] but declares no #{(hint == "it") ? "input #{key}" : hint}"
      end
    end
  end
end
