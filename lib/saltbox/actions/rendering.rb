module Saltbox
  module Actions
    # Gives actions the same `render` and `head` methods a Rails controller
    # has. `render :show` uses the model's view folder: events/show for Event,
    # event/types/show for Event::Type. A template anywhere else is named by
    # its full path. Instance variables set in #perform, and any locals, reach
    # the template just as they do from a controller. Views are rendered with
    # the configured controller's renderer (Configuration#renderer), the Rails
    # way to render outside a request.
    module Rendering
      # Instance variables the base class and its adapters set for themselves;
      # views never see them. Any starting @_ are left out too.
      PROTECTED_IVARS = %i[@actor @params @pundit].freeze
      # Tells render json: false or json: nil from no json: at all.
      NO_JSON = Object.new.freeze

      # @param template [Symbol, String, nil] :show, or "events/types/show"
      # @param status [Symbol, Integer]
      # @param json [Object] a body to send as is, with no view: any JSON value, false and nil included
      # @param meta [Hash, nil] meta beside the body, such as pagination (Result#meta)
      # @param locals [Hash] the template's locals
      # @return [Result]
      # @raise [AbstractController::DoubleRenderError] on a second render or head
      def render(template = nil, status: :ok, json: NO_JSON, meta: nil, **locals)
        raise AbstractController::DoubleRenderError if performed?
        body = if !json.equal?(NO_JSON)
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

      # @return [Hash{String => Object}] the action's own instance variables
      def view_assigns
        (instance_variables - PROTECTED_IVARS).reject { it.start_with?("@_") }.to_h { [it.to_s.delete_prefix("@"), instance_variable_get(it)] }
      end
    end
  end
end
