module Saltbox
  module Actions
    # Gives actions the same `render` and `head` methods a Rails controller
    # has. `render :show` uses the model's view folder: events/show for Event,
    # event/types/show for Event::Type. A member action's record is already
    # its view's instance variable (@event; see Base#member_record). A template anywhere else is named by
    # its full path. Instance variables set in #perform, and any locals, reach
    # the template just as they do from a controller. Views are rendered with
    # the configured controller's renderer (Configuration#renderer), the Rails
    # way to render outside a request.
    #
    # A list action whose model has a summary (Declarations#summarizes_list?)
    # renders it for every caller but a person on a screen (the API, MCP,
    # WebMCP and the assistant) in place of the view: each record in
    # `collection:`, or else in the model's plural instance variable
    # (@events), under data and the model's plural, with the meta beside it.
    # Screens get the view. Such an action always renders a template, and
    # always hands over its records, so nothing reaches an agent around the
    # summary.
    module Rendering
      # Instance variables the base class, Active Model and the adapters set
      # for themselves; views never see them. Any starting @_ are left out too.
      PROTECTED_IVARS = %i[@actor @params @pundit @attributes @errors @validation_context @context_for_validation].freeze
      # Tells render json: false or json: nil from no json: at all.
      NO_JSON = Object.new.freeze
      # Tells render collection: nil from no collection: at all.
      NO_COLLECTION = Object.new.freeze

      # @param template [Symbol, String, nil] :show, or "events/types/show"
      # @param status [Symbol, Integer]
      # @param json [Object] a body to send as is, with no view: any JSON value, false and nil included
      # @param meta [Hash, nil] meta beside the body, such as pagination (Result#meta)
      # @param collection [Enumerable] a list action's records, for one that keeps them elsewhere than @events;
      #   never a template local
      # @param locals [Hash] the template's locals
      # @return [Result]
      # @raise [AbstractController::DoubleRenderError] on a second render or head
      # @raise [ArgumentError] when a list action with a summary renders json:, or hands over no records,
      #   or another action passes collection:
      def render(template = nil, status: :ok, json: NO_JSON, meta: nil, collection: NO_COLLECTION, **locals)
        raise AbstractController::DoubleRenderError if performed?
        records = summarized_records(json, collection, meta)
        body = if records
          summaries(records, meta)
        elsif !json.equal?(NO_JSON)
          json.as_json
        else
          JSON.parse(Actions.config.renderer_class.render(template: template_path(template), formats: [:json], assigns: view_assigns, locals:))
        end
        @_result = Result.new(status: Rack::Utils.status_code(status), body:, meta:)
      end

      # @param status [Symbol, Integer]
      # @return [Result] a response with no body
      def head(status)
        raise AbstractController::DoubleRenderError if performed?
        @_result = Result.new(status: Rack::Utils.status_code(status), body: nil, empty: true)
      end

      # @return [Boolean] whether render or head has run
      def performed? = !@_result.nil?

      # @return [Result] the response, or a 204 when nothing was rendered
      def result = @_result || Result.no_content

      private

      def template_path(template)
        raise ArgumentError, "render needs a template, or json:" if template.nil?
        return template if template.to_s.include?("/")
        model = self.class.model
        raise ArgumentError, "#{self.class.name} has no model: name the template" unless model
        "#{model.model_name.collection}/#{template}"
      end

      # @return [Enumerable, nil] the records to summarize for this caller, or nil to render as asked
      # @raise [ArgumentError] when a list action with a summary would send agents anything else:
      #   json:, no records, or a record or relation in its meta
      def summarized_records(json, collection, meta)
        action = self.class
        unless action.summarizes_list?
          raise ArgumentError, "render collection: is for a list action with a summary; #{action.name} has none" unless collection.equal?(NO_COLLECTION)
          return
        end
        variable = "@#{action.model.model_name.plural}"
        unless json.equal?(NO_JSON)
          raise ArgumentError, "#{action.name} sends agents #{action.model.name}'s summary: render a template with #{variable} or collection:, not json:"
        end
        records = collection.equal?(NO_COLLECTION) ? instance_variable_get(variable) : collection
        unless records.respond_to?(:map) && !records.is_a?(Hash)
          raise ArgumentError, "#{action.name} sends agents #{action.model.name}'s summary: set #{variable} to its records, or render collection:"
        end
        plain_meta!(meta)
        records if actor.agent?
      end

      # The same JSON in either result format: {"data": {"events": [...]}, "meta": {...}}.
      # The envelope format wraps the body in data and adds the meta itself.
      def summaries(records, meta)
        summary = self.class.summary
        body = {self.class.model.model_name.plural => records.map { summary.call(it) }}
        return body if Actions.config.result_format == :envelope
        {"data" => body, "meta" => meta&.as_json}.compact
      end

      # What a summarized list's meta may hold, besides hashes and arrays of them.
      PLAIN_META = [String, Symbol, Numeric, TrueClass, FalseClass, NilClass, Date, Time].freeze

      # A summarized list's meta is the app's own plain data, such as paging:
      # anything else, a record or a set of them, would reach agents around
      # the summary.
      def plain_meta!(value, path = "meta")
        case value
        when ActiveRecord::Base, ActiveRecord::Relation then nil
        when Hash then return value.each { |key, item| plain_meta!(item, "#{path}.#{key}") }
        when Array then return value.each_with_index { |item, index| plain_meta!(item, "#{path}[#{index}]") }
        when *PLAIN_META then return
        end
        raise ArgumentError, "#{self.class.name} sends agents #{self.class.model.name}'s summary: #{path} holds a #{value.class}; " \
          "meta is plain data, such as paging: hashes, arrays, text, numbers, true or false, dates, times and nil"
      end

      # @return [Hash{String => Object}] the action's own instance variables
      def view_assigns
        (instance_variables - PROTECTED_IVARS).reject { it.start_with?("@_") }.to_h { [it.to_s.delete_prefix("@"), instance_variable_get(it)] }
      end
    end
  end
end
