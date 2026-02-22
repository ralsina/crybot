require "log"
require "json"
require "../../mcp/registry"
require "../../config/loader"

module Crybot
  module Web
    module Handlers
      class MCPHandler
        Log = ::Log.for("crybot.web.mcp")

        # Search MCP servers from registry
        def search_servers(env) : String
          query = env.params.query["q"]?
          limit = env.params.query["limit"]?.try(&.to_i?) || 20

          Log.debug { "[Web/MCP] Searching servers: query=#{query.inspect}, limit=#{limit}" }

          begin
            servers = ::Crybot::MCP::Registry.search(query, limit: limit)

            results = servers.map do |server|
              {
                name:             server.name,
                display_name:      server.display_name,
                description:      server.description,
                version:          server.version,
                transport:        server.transport_type.to_s,
                transport_display: server.transport_type.display_name,
                requires_auth:    server.requires_auth?,
                is_latest:        server.is_latest,
                is_official:      server.is_official,
                repository_url:   server.repository.try(&.url),
                website_url:      server.website_url,
                install_target:   server.installation_target,
                suggested_command: server.suggested_command,
              }
            end

            {success: true, servers: results, count: results.size}.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] Search failed" }
            error_response("Failed to search registry: #{e.message}")
          end
        end

        # Get server details from registry
        def get_server(env) : String
          server_name = env.params.url["server"]

          Log.debug { "[Web/MCP] Getting server: #{server_name}" }

          begin
            server = ::Crybot::MCP::Registry.get(server_name)

            if server.nil?
              return error_response("Server not found: #{server_name}")
            end

            {
              success:          true,
              name:             server.name,
              display_name:      server.display_name,
              description:      server.description,
              version:          server.version,
              title:            server.title,
              repository_url:   server.repository.try(&.url),
              website_url:      server.website_url,
              transport:        server.transport_type.to_s,
              transport_display: server.transport_type.display_name,
              requires_auth:    server.requires_auth?,
              is_latest:        server.is_latest,
              is_official:      server.is_official,
              install_target:   server.installation_target,
              suggested_command: server.suggested_command,
              packages: server.packages.map do |pkg|
                {
                  registry_type: pkg.registry_type,
                  identifier:    pkg.identifier,
                  version:       pkg.version,
                }
              end,
              remotes: server.remotes.map do |remote|
                {
                  type: remote.type,
                  url:  remote.url,
                }
              end,
            }.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] Get server failed" }
            error_response("Failed to get server: #{e.message}")
          end
        end

        # Install an MCP server
        def install_server(env) : String
          body = env.request.body.try(&.gets_to_end) || ""
          data = Hash(String, JSON::Any).from_json(body)

          server_name = data["server_name"]?.try(&.as_s?)

          if server_name.nil? || server_name.empty?
            return error_response("server_name is required")
          end

          Log.info { "[Web/MCP] Installing server: #{server_name}" }

          begin
            # Get server from registry
            server = ::Crybot::MCP::Registry.get(server_name)

            if server.nil?
              # Try search as fallback
              results = ::Crybot::MCP::Registry.search(server_name, limit: 5)
              if results.empty?
                return error_response("Server not found: #{server_name}")
              elsif results.size == 1
                server = results.first
              else
                # Multiple matches - return them for user to choose
                return {
                  success: false,
                  error:  "Multiple servers found",
                  matches: results.map do |s|
                    {name: s.name, description: s.description}
                  end,
                }.to_json
              end
            end

            server_obj = server.not_nil!

            # Generate config
            config = ::Crybot::MCP::Registry.generate_config(server_obj)

            # Add to config.yml
            add_server_to_config(config)

            # Reload MCP servers in running agent
            broadcast_reload_event

            Log.info { "[Web/MCP] Server installed: #{config.name}" }

            {
              success: true,
              message: "Server installed successfully",
              server: {
                name:     config.name,
                command:  config.command,
                url:      config.url,
                landlock: config.landlock.try { |ll|
                  {
                    allowed_paths: ll.allowed_paths,
                    allowed_ports: ll.allowed_ports,
                  }
                },
              },
            }.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] Install failed" }
            error_response("Failed to install server: #{e.message}")
          end
        end

        # List installed MCP servers
        def list_installed(env) : String
          Log.debug { "[Web/MCP] Listing installed servers" }

          begin
            config = Config::Loader.load
            servers = config.mcp.servers

            results = servers.map do |server|
              {
                name:     server.name,
                command:  server.command,
                url:      server.url,
                landlock: server.landlock.try do |ll|
                  {
                    allowed_paths: ll.allowed_paths,
                    allowed_ports: ll.allowed_ports,
                  }
                end,
              }
            end

            {success: true, servers: results, count: results.size}.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] List installed failed" }
            error_response("Failed to list servers: #{e.message}")
          end
        end

        # Uninstall an MCP server
        def uninstall_server(env) : String
          server_name = env.params.url["server"]

          Log.info { "[Web/MCP] Uninstalling server: #{server_name}" }

          begin
            home = ENV.fetch("HOME", "")
            if home.empty?
              return error_response("HOME environment variable not set")
            end

            config_path = File.join(home, ".crybot", "config.yml")

            unless File.exists?(config_path)
              return error_response("Config file not found")
            end

            config = Config::ConfigFile.from_yaml(File.read(config_path))

            if config.mcp.servers.none? { |s| s.name == server_name }
              return error_response("Server '#{server_name}' not found in config")
            end

            # Remove server
            config.mcp.servers.reject! { |s| s.name == server_name }

            # Write config
            File.write(config_path, config.to_yaml)

            # Reload MCP servers in running agent
            broadcast_reload_event

            Log.info { "[Web/MCP] Server uninstalled: #{server_name}" }

            {
              success: true,
              message: "Server '#{server_name}' uninstalled successfully",
            }.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] Uninstall failed" }
            error_response("Failed to uninstall server: #{e.message}")
          end
        end

        # Get server categories/featured servers
        def get_featured(env) : String
          Log.debug { "[Web/MCP] Getting featured servers" }

          begin
            # Return curated list of popular servers
            featured_names = [
              "ai.exa/exa",           # Web search
              "ai.mcpcap/mcpcap",     # PCAP analysis
              "ai.gossiper/shopify-admin-mcp",  # Shopify
              "ai.autoblocks/ctxl",   # Context management
            ]

            servers = featured_names.compact_map do |name|
              ::Crybot::MCP::Registry.get(name)
            end

            results = servers.map do |server|
              {
                name:             server.name,
                display_name:      server.display_name,
                description:      server.description,
                version:          server.version,
                transport_display: server.transport_type.display_name,
                is_official:      server.is_official,
              }
            end

            {success: true, featured: results, count: results.size}.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/MCP] Get featured failed" }
            error_response("Failed to get featured servers: #{e.message}")
          end
        end

        # Add server to config.yml
        private def add_server_to_config(server_config : Config::MCPServerConfig) : Nil
          home = ENV.fetch("HOME", "")
          if home.empty?
            raise "HOME environment variable not set"
          end

          config_path = File.join(home, ".crybot", "config.yml")

          # Load existing config
          config = if File.exists?(config_path)
                     Config::ConfigFile.from_yaml(File.read(config_path))
                   else
                     Config::ConfigFile.from_yaml("{}")
                   end

          # Check if server already exists - replace it
          if config.mcp.servers.any? { |s| s.name == server_config.name }
            Log.warn { "[Web/MCP] Server '#{server_config.name}' already exists, replacing" }
            config.mcp.servers.reject! { |s| s.name == server_config.name }
          end

          # Add server
          config.mcp.servers << server_config

          # Write config
          File.write(config_path, config.to_yaml)

          Log.debug { "[Web/MCP] Config updated" }
        end

        # Broadcast reload event to trigger MCP server reload
        private def broadcast_reload_event : Nil
          # Send message through WebSocket to trigger reload
          data = Hash(String, JSON::Any).new
          data["type"] = JSON::Any.new("mcp_reload")
          data["timestamp"] = JSON::Any.new(Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"))

          Crybot::Web::ChatSocket.broadcast("system_event", data)
        end

        # Generate error response
        private def error_response(message : String) : String
          {
            success: false,
            error:  message,
          }.to_json
        end
      end
    end
  end
end
