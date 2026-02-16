require "mcp-client"
require "../agent/tools/registry"
require "log"

module Crybot
  module MCP
    # MCP Client wrapper that uses the tested mcp-client library
    # and integrates with Crybot's tool registry
    class Client
      property client : ::MCP::Client?
      @server_name : String
      @tools : Array(::MCP::Tool) = [] of ::MCP::Tool

      def initialize(@server_name : String, @command : String? = nil, @url : String? = nil)
        raise "Either command or url must be provided" if @command.nil? && @url.nil?
      end

      def start : Nil
        command = @command
        return unless command

        parts = command.split(' ')
        cmd = parts.first
        args = parts[1..] || [] of String

        ::Log.info { "[MCP] Starting client for '#{@server_name}': #{cmd} #{args.join(' ')}" }

        @client = ::MCP::Client.new(cmd, args,
          client_name: "crybot",
          client_version: "0.1.0"
        )

        client = @client
        return unless client

        begin
          server_info = client.connect
          ::Log.info { "[MCP] Connected to '#{@server_name}': #{server_info.name} v#{server_info.version}" }
        rescue e : Exception
          ::Log.error { "[MCP] Failed to connect to '#{@server_name}': #{e.message}" }
          ::Log.debug { "[MCP] Error: #{e.class.name}" }
          return
        end

        # Cache tools
        @tools = client.list_tools
        ::Log.info { "[MCP] Found #{@tools.size} tools from '#{@server_name}'" }

        # Register tools with Crybot's registry
        register_tools
      end

      def stop : Nil
        if client = @client
          client.disconnect
        end
        @client = nil
      end

      def list_tools : Array(::MCP::Tool)
        @client.try &.list_tools || @tools
      end

      def call_tool(name : String, arguments : Hash(String, JSON::Any)) : ToolCallResult
        client = @client
        raise "MCP client not connected" unless client

        result = client.call_tool(name, arguments)
        ToolCallResult.new(content: result.content)
      end

      # Check if the server supports tools
      def supports_tools? : Bool
        @client.try &.supports_tools? || false
      end

      # Get server info if connected
      def server_capabilities : ::MCP::ServerCapabilities?
        @client.try &.server_capabilities
      end

      private def register_tools : Nil
        ::Log.info { "[MCP] Registering #{@tools.size} tools from '#{@server_name}'" }
        @tools.each do |tool|
          # Create a Crybot tool that wraps the MCP tool
          crybot_tool = MCPToolWrapper.new(@server_name, tool, self)
          tool_name = crybot_tool.name
          Tools::Registry.register(crybot_tool)
          ::Log.debug { "[MCP] Registered tool: #{tool_name}" }
        end
      end

      # Wrapper for MCP tools to integrate with Crybot's tool registry
      class MCPToolWrapper < Agent::Tools::Tool
        @server_name : String
        @mcp_tool : ::MCP::Tool

        def initialize(@server_name : String, @mcp_tool : ::MCP::Tool, @client : Client)
        end

        def name : String
          "#{@server_name}/#{@mcp_tool.name}"
        end

        def description : String
          @mcp_tool.description
        end

        def parameters : Hash(String, JSON::Any)
          @mcp_tool.input_schema
        end

        def execute(arguments : Hash(String, JSON::Any)) : String
          result = @client.call_tool(@mcp_tool.name, arguments)
          result.to_response_string
        end
      end
    end

    # Tool definition from MCP server
    struct Tool
      include JSON::Serializable

      property name : String
      property description : String
      property input_schema : Hash(String, JSON::Any)
    end

    # Tool call result from MCP server
    class ToolCallResult
      property content : Array(Hash(String, JSON::Any))

      def initialize(@content : Array(Hash(String, JSON::Any)))
      end

      def to_response_string : String
        @content.map do |item|
          if text = item["text"]?
            text.as_s
          elsif item["type"]?.try(&.as_s) == "resource"
            "Resource: #{item["uri"]?.try(&.as_s) || "unknown"}"
          else
            item.to_json
          end
        end.join("\n")
      end
    end
  end
end
