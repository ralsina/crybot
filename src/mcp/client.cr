require "mcp-client"
require "../agent/tools/registry"
require "log"
require "tool_runner"

module Crybot
  module MCP
    # MCP Client wrapper that uses the tested mcp-client library
    # and integrates with Crybot's tool registry
    class Client
      property client : ::MCP::Client?
      @server_name : String
      @tools : Array(::MCP::Tool) = [] of ::MCP::Tool
      @server_config : Config::MCPServerConfig?

      def initialize(@server_name : String, @command : String? = nil, @url : String? = nil, @server_config : Config::MCPServerConfig? = nil)
        raise "Either command or url must be provided" if @command.nil? && @url.nil?
      end

      def start : Nil
        command = @command
        return unless command

        parts = command.split(' ')
        cmd = parts.first
        args = parts[1..] || [] of String

        ::Log.info { "[MCP] Starting client for '#{@server_name}': #{cmd} #{args.join(' ')}" }

        # Create Landlock restrictions for this specific MCP server
        restrictions = create_restrictions_for_server

        ::Log.debug { "[MCP] Restrictions for '#{@server_name}': #{restrictions.path_rules.size} path rules" }

        # Create result channels for the isolated context
        client_channel = Channel(::MCP::Client?).new
        error_channel = Channel(Exception).new

        # Spawn MCP client in isolated context with Landlock restrictions
        _isolated_context = Fiber::ExecutionContext::Isolated.new("MCP-#{@server_name}", spawn_context: Fiber::ExecutionContext.default) do
          begin
            # Check if Landlock is globally disabled
            landlock_disabled = false
            begin
              # Access the Crybot module's landlock_disabled flag
              landlock_disabled = Crybot.landlock_disabled?
            rescue
              # If we can't access it (e.g., in tests), assume enabled
            end

            # Apply Landlock restrictions before spawning the MCP server
            if landlock_disabled
              ::Log.warn { "[MCP] Landlock DISABLED globally - MCP server running without sandboxing" }
            elsif ToolRunner::Landlock.available? && !restrictions.path_rules.empty?
              ::Log.info { "[MCP] Applying Landlock restrictions for '#{@server_name}'" }
              unless restrictions.apply
                error_channel.send(Exception.new("Failed to apply Landlock restrictions"))
                next
              end
              ::Log.debug { "[MCP] Landlock restrictions applied for '#{@server_name}'" }
            end

            # Create and connect the MCP client
            # The subprocess will inherit Landlock restrictions from this thread
            client = ::MCP::Client.new(cmd, args,
              client_name: "crybot",
              client_version: "0.1.0"
            )

            begin
              server_info = client.connect
              ::Log.info { "[MCP] Connected to '#{@server_name}': #{server_info.name} v#{server_info.version}" }
            rescue e : Exception
              ::Log.error { "[MCP] Failed to connect to '#{@server_name}': #{e.message}" }
              ::Log.debug { "[MCP] Error: #{e.class.name}" }
              error_channel.send(e)
              next
            end

            client_channel.send(client)
          rescue e : Exception
            error_channel.send(e)
          end
        end

        # Wait for connection result
        select
        when client_result = client_channel.receive
          if client = client_result
            @client = client

            # Cache tools
            @tools = client.list_tools
            ::Log.info { "[MCP] Found #{@tools.size} tools from '#{@server_name}'" }

            # Register tools with Crybot's registry
            register_tools
          else
            ::Log.error { "[MCP] Failed to start '#{@server_name}': no client returned" }
            @client = nil
          end
        when error = error_channel.receive
          ::Log.error { "[MCP] Failed to start '#{@server_name}': #{error.message}" }
          @client = nil
        end
      end

      private def create_restrictions_for_server : ToolRunner::Landlock::Restrictions
        # Check if this server has specific Landlock config
        if server_config = @server_config
          if landlock_config = server_config.landlock
            ::Log.info { "[MCP] Using custom Landlock config for '#{@server_name}'" }
            return build_restrictions_from_config(landlock_config)
          end
        end

        # No specific config - use default restrictions
        ::Log.debug { "[MCP] Using default Landlock restrictions for '#{@server_name}'" }
        build_default_restrictions
      end

      private def build_restrictions_from_config(config : Config::MCPLandlockConfig) : ToolRunner::Landlock::Restrictions
        restrictions = ToolRunner::Landlock::Restrictions.new

        # Always allow read-only access to system directories (needed for npm/node to work)
        restrictions.add_read_only("/usr")
        restrictions.add_read_only("/bin")
        restrictions.add_read_only("/lib")
        restrictions.add_read_only("/lib64")
        restrictions.add_read_only("/etc")
        restrictions.add_read_only("/proc")
        restrictions.add_read_only("/dev")

        # Add /dev/null specifically for writing
        restrictions.add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)

        # Add /tmp for general temp access
        restrictions.add_read_write("/tmp")

        # Add user-configured allowed paths
        home = ENV.fetch("HOME", "")
        config.allowed_paths.each do |path|
          expanded = path.starts_with?("~") ? path.sub("~", home) : path
          if Dir.exists?(expanded)
            restrictions.add_read_write(expanded)
            ::Log.debug { "[MCP] Added read-write path: #{expanded}" }
          else
            ::Log.warn { "[MCP] Configured path does not exist: #{expanded}" }
          end
        end

        # Add common npm/node paths if they exist
        if !home.empty?
          npm_cache = File.join(home, ".npm")
          node_modules = File.join(home, "node_modules")
          restrictions.add_read_only(npm_cache) if Dir.exists?(npm_cache)
          restrictions.add_read_only(node_modules) if Dir.exists?(node_modules)
        end

        restrictions
      end

      private def build_default_restrictions : ToolRunner::Landlock::Restrictions
        # Use default_crybot restrictions for MCP servers without specific config
        restrictions = ToolRunner::Landlock::Restrictions.default_crybot

        # Add npm/node paths
        home = ENV.fetch("HOME", "")
        if !home.empty?
          npm_cache = File.join(home, ".npm")
          node_modules = File.join(home, "node_modules")
          restrictions.add_read_only(npm_cache) if Dir.exists?(npm_cache)
          restrictions.add_read_only(node_modules) if Dir.exists?(node_modules)
        end

        restrictions
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
