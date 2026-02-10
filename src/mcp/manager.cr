require "../agent/tools/registry"
require "../agent/tools/base"
require "./client"

module Crybot
  module MCP
    # Manages MCP server connections and tool registration
    class Manager
      @clients : Hash(String, Client) = {} of String => Client

      def initialize(config : Config::MCPConfig?)
        return unless config

        config.servers.each do |server_config|
          begin
            client = Client.new(server_config.name, server_config.command, server_config.url)
            client.start
            @clients[server_config.name] = client

            puts "[MCP] Connected to server '#{server_config.name}' - #{client.list_tools.size} tools available"
          rescue e : Exception
            puts "[MCP] Failed to connect to server '#{server_config.name}': #{e.message}"
          end
        end
      end

      def stop : Nil
        @clients.each_value(&.stop)
        @clients.clear
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

            results << {name: server_config.name, status: "connected", error: nil}
          rescue e : Exception
            results << {name: server_config.name, status: "failed", error: e.message}
          end
        end

        results
      end

      # Get status of all servers
      def status : Array(NamedTuple(name: String, status: String, error: String?))
        @clients.map do |name, _|
          {name: name, status: "connected", error: nil}
        end
      end
    end
  end
end
