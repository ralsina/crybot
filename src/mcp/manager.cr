require "../agent/tools/registry"
require "../agent/tools/base"
require "./client"

module Crybot
  module MCP
    # Manages MCP server connections and tool registration
    class Manager
      @clients : Hash(String, Client) = {} of String => Client
      @mcp_tools : Hash(String, MCPTool) = {} of String => MCPTool

      def initialize(config : Config::MCPConfig?)
        return unless config

        config.servers.each do |server_config|
          begin
            client = Client.new(server_config.name, server_config.command, server_config.url)
            client.start
            @clients[server_config.name] = client

            # Register tools from this server
            register_tools_from_server(client, server_config.name)

            puts "[MCP] Connected to server '#{server_config.name}'"
          rescue e : Exception
            puts "[MCP] Failed to connect to server '#{server_config.name}': #{e.message}"
          end
        end
      end

      def stop : Nil
        @clients.each_value(&.stop)
        @clients.clear
        @mcp_tools.clear
      end

      # Reload MCP servers with new configuration
      def reload(config : Config::MCPConfig?) : Array(NamedTuple(name: String, status: String, error: String?))
        results = [] of NamedTuple(name: String, status: String, error: String?)

        # Stop all existing clients
        stop

        return results unless config

        config.servers.each do |server_config|
          begin
            client = Client.new(server_config.name, server_config.command, server_config.url)
            client.start
            @clients[server_config.name] = client

            # Register tools from this server
            register_tools_from_server(client, server_config.name)

            results << {name: server_config.name, status: "connected", error: nil}
            puts "[MCP] Reloaded server '#{server_config.name}'"
          rescue e : Exception
            results << {name: server_config.name, status: "error", error: e.message}
            puts "[MCP] Failed to reload server '#{server_config.name}': #{e.message}"
          end
        end

        results
      end

      private def register_tools_from_server(client : Client, server_name : String) : Nil
        tools = client.list_tools

        tools.each do |tool|
          mcp_tool = MCPTool.new(client, tool)
          @mcp_tools["#{server_name}/#{tool.name}"] = mcp_tool

          # Register with Crybot's tool registry
          crybot_tool = MCPToolWrapper.new(mcp_tool)
          Agent::Tools::Registry.register(crybot_tool)

          puts "[MCP] Registered tool: #{server_name}/#{tool.name}"
        end
      end
    end

    # Represents a tool from an MCP server
    class MCPTool
      property client : Client
      property tool : Client::Tool

      def initialize(@client : Client, @tool : Client::Tool)
      end

      def execute(arguments : Hash(String, JSON::Any)) : String
        result = @client.call_tool(@tool.name, arguments)
        result.to_response_string
      end
    end

    # Wraps an MCP tool to implement Crybot's Tool interface
    class MCPToolWrapper < Agent::Tools::Tool
      @mcp_tool : MCPTool

      def initialize(@mcp_tool : MCPTool)
      end

      def name : String
        @mcp_tool.tool.name
      end

      def description : String
        @mcp_tool.tool.description || "MCP tool: #{name}"
      end

      def parameters : Hash(String, JSON::Any)
        @mcp_tool.tool.input_schema
      end

      def execute(args : Hash(String, JSON::Any)) : String
        @mcp_tool.execute(args)
      end
    end
  end
end
