module Saltbox
  module Actions
    # The catalog and the run endpoint for a JSON API: every action, on one
    # route. Include it in a controller and define #resolve_caller, which
    # decides who is calling from the request's credential and nothing else.
    #
    #   GET  /api/v1/actions          the actions this caller may use
    #   GET  /api/v1/actions/:name    one action's definition
    #   POST /api/v1/actions/:name    runs it with {"arguments": {...}}; answers with the action's response
    #
    # @example config/routes.rb
    #   get "actions", to: "actions#index"
    #   get "actions/:name", to: "actions#show"
    #   post "actions/:name", to: "actions#run"
    #
    # @example
    #   class Api::V1::ActionsController < ApplicationController
    #     include Saltbox::Actions::Controller
    #
    #     private
    #
    #     def resolve_caller = ApplicationAction::Caller.screen(Current.account)
    #   end
    module Controller
      extend ActiveSupport::Concern

      included do
        # The body is {"arguments": {...}}; a wrapped copy would read as an
        # unknown field.
        wrap_parameters false
        around_action :as_action_caller
        rescue_from Error, with: :render_action_error
        rescue_from ActionDispatch::Http::Parameters::ParseError do
          render_action_error(Error::Invalid.new("The request body is not valid JSON"))
        end
      end

      # @return [void] the caller's catalog, with an ETag
      def index
        entries = Registry.catalog(@action_caller)
        json = JSON.generate({data: entries, meta: {version: Registry.version, api_version: "v1", count: entries.size}})
        render json: json if stale?(etag: Digest::SHA256.hexdigest(json), public: false)
      end

      # @return [void] one definition the caller can see
      def show
        entry = Registry.catalog(@action_caller).find { |candidate| candidate["name"] == params[:name] }
        raise Error::UnknownAction, params[:name] unless entry
        render json: {data: entry}
      end

      # @return [void] the action's response body and status
      def run
        result = Invocation.call(name: params[:name], caller: @action_caller, arguments: run_arguments)
        return head(result.status) if result.empty?
        # Encoded here, once: Rails sends a String given as json: as is, so
        # a body that is a JSON string would not arrive quoted.
        render json: JSON.generate(result.as_json), status: result.status
      end

      private

      # @return [Caller] who is calling, from the request's credential; never Caller.system
      def resolve_caller = raise(NotImplementedError, "#{self.class.name} must define resolve_caller")

      def as_action_caller
        @action_caller = Caller.from_request!(resolve_caller, self.class.name)
        yield
      end

      # The body's "arguments", exactly as the JSON sent them: the action's
      # JSON Schema checks them, so a false or a string is refused there with
      # a field error rather than dropped here. Rails parses a body that is
      # not an object into "_json".
      def run_arguments
        fields = request.request_parameters
        raise Error::Invalid, 'Send a JSON object: {"arguments": {...}}' if fields.key?("_json")
        unknown = fields.keys - ["arguments"]
        if unknown.any? && !request.media_type.to_s.end_with?("json")
          raise Error::Invalid, "The body was not read as JSON: send it with Content-Type: application/json"
        end
        raise Error::Invalid, "Unknown fields: #{unknown.join(", ")}. Put the action's arguments in \"arguments\"." if unknown.any?
        fields["arguments"]
      end

      def render_action_error(error)
        response.headers["WWW-Authenticate"] = "Bearer" if error.is_a?(Error::Unauthorized)
        render json: error.as_json, status: error.status
      end
    end
  end
end
