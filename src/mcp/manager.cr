require "../agent/tools/registry"
require "../agent/tools/base"
require "./client"
require "log"

module Crybot
  module MCP
    # Manages MCP server connections and tool registration
    # Singleton pattern - only one instance shared across all agent loops
    # MCP servers have per-server locks to prevent concurrent access
    class Manager
      @@instance : Manager?

      @clients : Hash(String, Client) = {} of String => Client
      @server_locks : Hash(String, Mutex) = {} of String => Mutex
      @config : Config::MCPConfig?
      @started : Bool = false
      @mutex : Mutex = Mutex.new

      def initialize(@config : Config::MCPConfig?)
        # Don't start servers during initialization - do it lazily
      end

      # Get or create the singleton MCP manager instance
      # Config is only used on first call - subsequent calls ignore it
      def self.instance(config : Config::MCPConfig?) : Manager
        if manager = @@instance
          manager
        else
          @@instance = Manager.new(config)
        end
      end

      # Update the config (used during reload)
      private def update_config(config : Config::MCPConfig?) : Nil
        @config = config if config
      end

      # Reset the singleton (useful for testing or config reload)
      def self.reset : Nil
        @@instance.try(&.stop)
        @@instance = nil
      end

      # Acquire a lock for a specific server
      # Returns the lock mutex
      def get_server_lock(server_name : String) : Mutex
        @mutex.synchronize do
          @server_locks[server_name] ||= Mutex.new
        end
      end

      # Start MCP servers in the background (called after agent is ready)
      # Only starts once - subsequent calls are no-ops
      def start_async : Nil
        @mutex.synchronize do
          return if @started
          @started = true
        end

        config = @config
        return unless config

        spawn do
          config.servers.each do |server_config|
            begin
              client = Client.new(server_config.name, server_config.command, server_config.url, server_config)
              client.start
              @clients[server_config.name] = client

              ::Log.info { "[MCP] Connected to server '#{server_config.name}' - #{client.list_tools.size} tools available" }
            rescue e : Exception
              ::Log.error { "[MCP] Failed to connect to server '#{server_config.name}': #{e.message}" }
            end
          end
        end
      end

      def stop : Nil
        @mutex.synchronize do
          @clients.each_value(&.stop)
          @clients.clear
          @server_locks.clear
          @started = false
        end
      end

      # Reload MCP servers with new configuration
      def reload(config : Config::MCPConfig?) : Array(NamedTuple(name: String, status: String, error: String?))
        @mutex.synchronize do
          # Stop all existing clients
          @clients.each_value(&.stop)
          @clients.clear
          @started = false

          # Update config
          update_config(config)
        end

        results = [] of NamedTuple(name: String, status: String, error: String?)

        unless config
          return results
        end

        # Restart with new config
        start_async

        # Note: We return success immediately since start_async is async
        # In a real scenario, you might want to wait for confirmation
        config.servers.each do |server_config|
          results << {name: server_config.name, status: "reloading", error: nil}
        end

        results
      end

      # Get status of all servers
      def status : Array(NamedTuple(name: String, status: String, error: String?))
        @mutex.synchronize do
          @clients.map do |name, _|
            {name: name, status: "connected", error: nil}
          end
        end
      end
    end
  end
end
