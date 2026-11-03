require "mcp"

module Saltbox
  module Actions
    module Adapters
      module EntryPoints
        # Serves the agent tools over the Model Context Protocol with the `mcp`
        # gem: stateless streamable HTTP, JSON responses, one server per request
        # built for the caller its credential names. The app keeps the
        # credential check and mounts a Rack endpoint that calls MCP.call.
        #
        # @example config/routes.rb
        #   mount Mcp::Endpoint.new, at: "/mcp"
        #
        # @example app/tools/mcp/endpoint.rb
        #   class Mcp::Endpoint
        #     def call(env)
        #       caller = ApiToken.caller_for(env["HTTP_AUTHORIZATION"], surface: "mcp")
        #       return unauthorized unless caller
        #       Saltbox::Actions::Adapters::EntryPoints::MCP.call(env, caller:, name: "acme", allowed_hosts: [api_host])
        #     end
        #   end
        module MCP
          # A server whose tool calls all go through the agent tools, so a name
          # cached from an earlier tools/list is checked again on every call.
          # @api private
          class Server < ::MCP::Server
            private

            def call_tool(request, **)
              arguments = request.key?(:arguments) ? request[:arguments] : {}
              MCP.invoke(request[:name], arguments, server_context.fetch(:caller)).to_h
            end
          end

          # @param caller [Caller]
          # @return [Array<Class<::MCP::Tool>>] the tools this caller can discover
          # @api private
          def self.tools(caller)
            AgentTools.tools(caller).map do |tool|
              ::MCP::Tool.define(name: tool.name, title: tool.title, description: tool.description,
                input_schema: tool.input_schema, annotations: tool.annotations)
            end
          end

          # @param name [String] a direct tool, find_action or a run tool
          # @param arguments [Hash, nil] the tool's arguments
          # @param caller [Caller]
          # @return [::MCP::Tool::Response] the result, or the refusal as a tool error the model can read
          # @api private
          def self.invoke(name, arguments, caller)
            # MCP requires an object even for explicit null. AgentTools takes
            # nil as left out, so pass a value it refuses. Invocation still admits
            # the caller before it checks that value.
            arguments = false if arguments.nil?
            result = AgentTools.call(name, arguments, caller:)
            # A tool result needs content, so a response with no body, such as a
            # delete's 204, becomes "Done.".
            return ::MCP::Tool::Response.new([{type: "text", text: "Done."}]) if result.equal?(AgentTools::EMPTY)
            # Structured content is an object, unmarked; any other JSON value goes
            # as text alone. The text is marked as record data (see RecordData).
            ::MCP::Tool::Response.new([{type: "text", text: RecordData.wrap(result)}], structured_content: (result if result.is_a?(Hash)))
          rescue Error => error
            ::MCP::Tool::Response.new([{type: "text", text: RecordData.wrap(error.as_json)}],
              error: true, structured_content: error.as_json, meta: {code: error.code, errors: error.errors}.compact)
          end

          # @return [String] RecordData::NOTE, then the app's own config.instructions
          def self.instructions
            [RecordData::NOTE, Actions.config.instructions.presence].compact.join("\n\n")
          end

          # @param caller [Caller]
          # @param name [String] the server's name
          # @param title [String] the server's title; the app's name by default
          # @return [Server]
          # @api private
          def self.server(caller, name:, title: Actions.config.app_name)
            Server.new(name:, title:, version: Registry.version, instructions: instructions,
              tools: tools(caller), server_context: {caller:}, capabilities: {tools: {listChanged: false}})
          end

          # Answers one MCP request for the caller.
          #
          # @param env [Hash] the Rack environment
          # @param caller [Caller] from the request's credential
          # @param name [String] the server's name
          # @param allowed_hosts [Array<String>] the hosts the server answers on
          # @param max_request_bytes [Integer]
          # @return [Array(Integer, Hash, Array)] the Rack response, never cached
          def self.call(env, caller:, name:, allowed_hosts:, max_request_bytes: 1.megabyte)
            transport = ::MCP::Server::Transports::StreamableHTTPTransport.new(server(caller, name:),
              stateless: true, enable_json_response: true, allowed_hosts:,
              serve_subscriptions_listen: false, max_request_bytes:)
            status, headers, body = transport.call(env)
            [status, headers.merge("cache-control" => "no-store"), body]
          end
        end
      end
    end
  end
end
