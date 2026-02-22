require "log"
require "option_parser"
require "../mcp/registry"
require "../config/loader"
require "../config/schema"

module Crybot
  module Commands
    module MCP
      Log = ::Log.for("crybot.commands.mcp")

      # Run MCP commands
      def self.run(args : Array(String)) : Nil
        if args.empty?
          show_help
          return
        end

        command = args[0]

        case command
        when "search"
          handle_search(args[1..])
        when "install"
          handle_install(args[1..])
        when "list"
          handle_list(args[1..])
        when "uninstall"
          handle_uninstall(args[1..])
        else
          Log.error { "Unknown MCP command: #{command}" }
          show_help
        end
      end

      # Search for MCP servers
      private def self.handle_search(args : Array(String)) : Nil
        query = args.first?

        Log.info { "Searching MCP registry..." }

        begin
          results = ::Crybot::MCP::Registry.search(query, limit: 20)

          if results.empty?
            if query.nil? || query.empty?
              Log.info { "No servers found in registry" }
            else
              Log.info { "No servers found matching '#{query}'" }
            end
            return
          end

          display_search_results(results, query)
        rescue e : ::Crybot::MCP::RegistryError
          Log.error { "Failed to search registry: #{e.message}" }
          exit 1
        rescue e : Exception
          Log.error(exception: e) { "Error searching registry" }
          exit 1
        end
      end

      # Display search results
      private def self.display_search_results(results : Array(::Crybot::MCP::Registry::ServerInfo), query : String?) : Nil
        if query.nil? || query.empty?
          puts "Found #{results.size} server#{results.size == 1 ? "" : "s"}:"
        else
          puts "Found #{results.size} server#{results.size == 1 ? "" : "s"} matching '#{query}':"
        end
        puts

        results.each_with_index do |server, idx|
          puts "#{idx + 1}".colorize.bold.to_s + ". " + server.name.colorize.cyan.to_s
          puts "   #{server.description}"

          if server.is_official
            puts "   " + "[OFFICIAL]".colorize.green.to_s + " v#{server.version}"
          else
            puts "   v#{server.version}"
          end

          # Show transport info
          transport_info = server.transport_type.display_name
          if server.needs_url?
            puts "   Transport: " + transport_info.colorize.yellow.to_s + " → #{server.installation_target}"
          elsif cmd = server.suggested_command
            puts "   Transport: " + transport_info.colorize.yellow.to_s + " → #{cmd.colorize.bold}"
          end

          # Show auth requirement
          if server.requires_auth?
            puts "   " + "⚠ Requires authentication".colorize.yellow.to_s
          end

          puts
        end

        puts "Install with: " + "crybot mcp install <server-name>".colorize.bold.to_s
      end

      # Install an MCP server
      private def self.handle_install(args : Array(String)) : Nil
        if args.empty?
          Log.error { "Usage: crybot mcp install <server-name>" }
          exit 1
        end

        server_name = args[0]

        Log.info { "Looking up server: #{server_name}" }

        begin
          # Try exact match first
          server = ::Crybot::MCP::Registry.get(server_name)

          # If not found, try search
          if server.nil?
            results = ::Crybot::MCP::Registry.search(server_name, limit: 5)
            if results.empty?
              Log.error { "Server '#{server_name}' not found in registry" }
              Log.info { "Try 'crybot mcp search #{server_name}' to find similar servers" }
              exit 1
            elsif results.size == 1 || results.any? { |s| s.name == server_name }
              server = results.find { |s| s.name == server_name } || results.first
            else
              # Multiple matches, show selection
              Log.info { "Multiple servers found:" }
              results.each_with_index do |s, idx|
                puts "#{idx + 1}. #{s.name} - #{s.description}"
              end
              Log.error { "Please be more specific" }
              exit 1
            end
          end

          if server_obj = server
            install_server(server_obj)
          else
            Log.error { "Server lookup returned nil" }
            exit 1
          end
        rescue e : ::Crybot::MCP::RegistryError
          Log.error { "Failed to fetch server: #{e.message}" }
          exit 1
        rescue e : Exception
          Log.error(exception: e) { "Error installing server" }
          exit 1
        end
      end

      # Install a server interactively
      private def self.install_server(server : ::Crybot::MCP::Registry::ServerInfo) : Nil
        puts "\n" + "=".colorize.bold.to_s * 60
        puts "Installing MCP Server".colorize.bold.to_s
        puts "=".colorize.bold.to_s * 60
        puts
        puts "Name:".colorize.bold.to_s + " #{server.name}"
        puts "Description:".colorize.bold.to_s + " #{server.description}"
        puts "Version:".colorize.bold.to_s + " #{server.version}"
        puts

        # Show transport info
        if server.needs_url?
          puts "Transport:".colorize.bold.to_s + " HTTP (streamable)"
          puts "URL:".colorize.bold.to_s + " #{server.installation_target}"
        elsif cmd = server.suggested_command
          puts "Transport:".colorize.bold.to_s + " #{server.transport_type.display_name}"
          puts "Command:".colorize.bold.to_s + " #{cmd.colorize.cyan}"
        end
        puts

        # Show auth requirement
        if server.requires_auth?
          puts "⚠ ".colorize.yellow.to_s + "This server requires authentication"
          puts
        end

        # Show Landlock restrictions
        puts "Landlock Restrictions:".colorize.bold.to_s
        puts "  - Default Crybot restrictions (read-only system paths, read-write workspace/playground)"

        # Add suggested restrictions based on server type
        if server.description.downcase.includes?("database") ||
           server.description.downcase.includes?("storage")
          puts "  - Additional read-write access to ~/.crybot/data"
        end
        puts

        # Confirm installation
        print "Install this server? [y/N] ".colorize.bold.to_s
        response = gets

        if response.nil? || response.empty? || !response.downcase.starts_with?('y')
          Log.info { "Installation cancelled" }
          return
        end

        # Generate config
        begin
          config = ::Crybot::MCP::Registry.generate_config(server)
          add_server_to_config(config)

          puts
          puts "✓ Server installed successfully!".colorize.green.bold
          puts
          puts "Added to config.yml:"
          puts "  - Name: #{config.name}"
          puts "  - " + (config.url ? "URL: #{config.url}" : "Command: #{config.command}")

          # Suggest restart
          puts
          print "Restart Crybot to load the new server? [y/N] ".colorize.bold.to_s
          restart_response = gets

          if restart_response && !restart_response.empty? && restart_response.downcase.starts_with?('y')
            Log.info { "Restarting..." }
            # Trigger restart via config watcher
            if exec_path = Process.executable_path
              Process.exec(exec_path, ARGV)
            else
              Log.error { "Cannot determine executable path for restart" }
            end
          else
            Log.info { "Server will be available on next restart" }
          end
        rescue e : Exception
          Log.error(exception: e) { "Failed to add server to config" }
          exit 1
        end
      end

      # Add server to config.yml
      private def self.add_server_to_config(server_config : Config::MCPServerConfig) : Nil
        home = ENV.fetch("HOME", "")
        if home.empty?
          raise "HOME environment variable not set"
        end

        config_path = File.join(home, ".crybot", "config.yml")

        # Load existing config
        config = if File.exists?(config_path)
                   Config::ConfigFile.from_yaml(File.read(config_path))
                 else
                   # Create minimal config from YAML
                   Config::ConfigFile.from_yaml("{}")
                 end

        # Check if server already exists
        if config.mcp.servers.any? { |s| s.name == server_config.name }
          Log.warn { "Server '#{server_config.name}' already exists in config" }
          print "Overwrite? [y/N] ".colorize.yellow.to_s
          response = gets

          if response.nil? || response.empty? || !response.downcase.starts_with?('y')
            Log.info { "Skipping installation" }
            return
          end

          # Remove existing server
          config.mcp.servers.reject! { |s| s.name == server_config.name }
        end

        # Add server
        config.mcp.servers << server_config

        # Write config
        File.write(config_path, config.to_yaml)

        Log.debug { "Updated config.yml" }
      end

      # List installed MCP servers
      private def self.handle_list(args : Array(String)) : Nil
        config = Config::Loader.load
        servers = config.mcp.servers

        if servers.nil? || servers.empty?
          Log.info { "No MCP servers installed" }
          Log.info { "Search with: crybot mcp search <query>" }
          return
        end

        puts "Installed MCP Servers:"
        puts

        servers.each_with_index do |server, idx|
          puts "#{idx + 1}.".colorize.bold.to_s + " #{server.name.colorize.cyan}"

          if server.url
            puts "   URL: #{server.url}"
          elsif server.command
            puts "   Command: #{server.command}"
          end

          if ll_config = server.landlock
            if !ll_config.allowed_paths.empty? || !ll_config.allowed_ports.empty?
              puts "   Landlock:"
              ll_config.allowed_paths.each do |path|
                puts "     - #{path}"
              end
              ll_config.allowed_ports.each do |port|
                puts "     - Port: #{port}"
              end
            end
          else
            puts "   Landlock: Default restrictions"
          end

          puts
        end
      end

      # Uninstall an MCP server
      private def self.handle_uninstall(args : Array(String)) : Nil
        if args.empty?
          Log.error { "Usage: crybot mcp uninstall <server-name>" }
          exit 1
        end

        server_name = args[0]

        home = ENV.fetch("HOME", "")
        if home.empty?
          raise "HOME environment variable not set"
        end

        config_path = File.join(home, ".crybot", "config.yml")

        unless File.exists?(config_path)
          Log.error { "Config file not found" }
          exit 1
        end

        config = Config::ConfigFile.from_yaml(File.read(config_path))
        servers = config.mcp.servers

        if servers.nil? || servers.none? { |s| s.name == server_name }
          Log.error { "Server '#{server_name}' not found in config" }
          exit 1
        end

        print "Uninstall server '#{server_name}'? [y/N] ".colorize.yellow.to_s
        response = gets

        if response.nil? || response.empty? || !response.downcase.starts_with?('y')
          Log.info { "Uninstall cancelled" }
          return
        end

        config.mcp.servers = servers.reject { |s| s.name == server_name }

        File.write(config_path, config.to_yaml)

        puts "✓ Server '#{server_name}' uninstalled".colorize.green
        Log.info { "Restart Crybot to apply changes" }
      end

      # Show help
      private def self.show_help : Nil
        puts <<-HELP
        MCP Server Management

        Usage:
          crybot mcp search [query]     Search for MCP servers
          crybot mcp install <name>     Install an MCP server from the registry
          crybot mcp list               List installed MCP servers
          crybot mcp uninstall <name>   Uninstall an MCP server

        Examples:
          crybot mcp search spotify
          crybot mcp install ai.exa/exa
          crybot mcp list

        For more information, see: https://registry.modelcontextprotocol.io
        HELP
      end
    end
  end
end
