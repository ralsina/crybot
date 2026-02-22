require "http/client"
require "json"
require "log"

module Crybot
  module MCP
    # Client for the official MCP Registry API
    # https://registry.modelcontextprotocol.io
    class Registry
      API_BASE         = "https://registry.modelcontextprotocol.io"
      SERVERS_ENDPOINT = "/v0/servers"

      Log = ::Log.for("crybot.mcp.registry")

      # Cache for fetched servers (expires after 1 hour)
      @@cached_servers : Array(ServerInfo)?
      @@cache_time : Time?
      CACHE_TTL = 1.hour

      # Clear the cache (useful for testing)
      def self.clear_cache : Nil
        @@cached_servers = nil
        @@cache_time = nil
      end

      # Server information from the registry
      struct ServerInfo
        include JSON::Serializable

        property name : String
        property description : String
        property version : String
        property title : String?
        property repository : Repository?
        property website_url : String?
        property icons : Array(Icon)?
        property packages : Array(Package) = [] of Package
        property remotes : Array(Remote) = [] of Remote
        property environment_variables : Array(EnvVar)?
        property is_latest : Bool = false
        property is_official : Bool = false

        # Get the transport type for this server
        def transport_type : TransportType
          if remote = remotes.first?
            case remote.type
            when "streamable-http" then TransportType::StreamableHttp
            when "sse"             then TransportType::SSE
            else                        TransportType::Unknown
            end
          elsif pkg = packages.first?
            case pkg.registry_type
            when "npm"  then TransportType::NPM
            when "pypi" then TransportType::PyPI
            when "oci"  then TransportType::OCI
            else             TransportType::Unknown
            end
          else
            TransportType::Unknown
          end
        end

        # Get the installation command/url for this server
        def installation_target : String?
          if remote = remotes.first?
            remote.url
          elsif pkg = packages.first?
            pkg.identifier
          end
        end

        # Determine if this needs a command or url configuration
        def needs_url? : Bool
          !remotes.empty?
        end

        # Get suggested command based on package type
        def suggested_command : String?
          return nil if packages.empty?

          pkg = packages.first
          case pkg.registry_type
          when "npm"
            "npx #{pkg.identifier}"
          when "pypi"
            "uvx #{pkg.identifier}"
          when "oci"
            "docker run #{pkg.identifier}"
          else
            nil
          end
        end

        # Get a short display name (strip ai. prefix if present)
        def display_name : String
          name.sub(/^ai\.[^\.]+\//, "")
        end

        # Check if server requires authentication
        def requires_auth? : Bool
          remotes.any? { |r| r.headers.try(&.any?) || false }
        end
      end

      struct Repository
        include JSON::Serializable

        property url : String = ""
        property source : String? # "github", etc.
      end

      struct Icon
        include JSON::Serializable

        property src : String
        property mime_type : String?
        property theme : String?
      end

      struct Package
        include JSON::Serializable

        @[JSON::Field(key: "registryType")]
        property registry_type : String

        property identifier : String
        property version : String?
        property transport : Transport?
        property environment_variables : Array(EnvVar)?
      end

      struct Remote
        include JSON::Serializable

        property type : String
        property url : String
        property headers : Array(EnvVar)?
        property variables : Hash(String, Variable)?
      end

      struct Transport
        include JSON::Serializable

        property type : String
      end

      struct EnvVar
        include JSON::Serializable

        property name : String
        property description : String?
        property format : String?
        @[JSON::Field(key: "isSecret")]
        property is_secret : Bool?
        @[JSON::Field(key: "isRequired")]
        property is_required : Bool?
      end

      struct Variable
        include JSON::Serializable

        property description : String?
        property format : String?
        property default : String?
      end

      enum TransportType
        NPM
        PyPI
        OCI
        StreamableHttp
        SSE
        Unknown

        def display_name : String
          case self
          when NPM            then "npm (npx)"
          when PyPI           then "Python (uvx)"
          when OCI            then "Docker"
          when StreamableHttp then "HTTP"
          when SSE            then "SSE"
          when Unknown        then "Unknown"
          else                     "Unknown"
          end
        end
      end

      # Response from the registry API
      struct RegistryResponse
        include JSON::Serializable

        property servers : Array(ServerEntry)
        property metadata : Metadata

        struct ServerEntry
          include JSON::Serializable

          property server : ServerInfo
          property _meta : Hash(String, JSON::Any)?
        end

        struct Metadata
          include JSON::Serializable

          @[JSON::Field(key: "nextCursor")]
          property next_cursor : String?

          property count : Int32
        end
      end

      # Search for MCP servers by query using the registry API
      # Returns only the latest version of each server
      def self.search(query : String? = nil, limit : Int32 = 50) : Array(ServerInfo)
        # Use registry API's built-in search for faster results
        if query && !query.empty?
          return search_api(query, limit)
        end

        # For empty query, return featured/official servers
        servers = fetch_servers

        # Filter to official and latest only for empty query
        servers.select { |s| s.is_official && s.is_latest }.first(limit)
      end

      # Search using the registry API's search endpoint
      private def self.search_api(query : String, limit : Int32) : Array(ServerInfo)
        all_servers = [] of ServerInfo
        cursor : String? = nil

        loop do
          url = "#{API_BASE}#{SERVERS_ENDPOINT}"
          params = [] of String
          params << "search=#{URI.encode_path_segment(query)}"
          if limit && all_servers.size < limit
            params << "limit=#{Math.min(limit - all_servers.size, 100)}"
          end
          if cursor
            params << "cursor=#{URI.encode_path_segment(cursor)}"
          end
          url += "?#{params.join("&")}"

          Log.debug { "Searching registry: #{url}" }

          response = HTTP::Client.get(url)

          unless response.success?
            Log.error { "Registry API returned #{response.status_code}: #{response.status_message}" }
            raise RegistryError.new("Failed to search registry: #{response.status_code}")
          end

          registry_response = RegistryResponse.from_json(response.body)

          # Extract server info and mark official status
          registry_response.servers.each do |entry|
            server = entry.server
            if meta = entry._meta
              if official = meta["io.modelcontextprotocol.registry/official"]?
                server.is_official = official["status"]?.try(&.as_s) == "active"
                server.is_latest = official["isLatest"]?.try(&.as_bool) || false
              end
            end
            all_servers << server
          end

          # Check if we have enough results or there's no next page
          break if all_servers.size >= limit
          cursor = registry_response.metadata.next_cursor
          break if cursor.nil? || cursor.empty?
        end

        Log.info { "Search returned #{all_servers.size} servers" }
        all_servers.first(limit)
      end

      # Get a specific server by name
      def self.get(server_name : String) : ServerInfo?
        servers = fetch_servers
        servers.find { |s| s.name == server_name && s.is_latest }
      end

      # Fetch all servers from the registry
      private def self.fetch_servers : Array(ServerInfo)
        all_servers = [] of ServerInfo
        cursor : String? = nil

        loop do
          url = "#{API_BASE}#{SERVERS_ENDPOINT}"
          if cursor
            url += "?cursor=#{URI.encode_path_segment(cursor)}"
          end

          Log.debug { "Fetching from registry: #{url}" }

          response = HTTP::Client.get(url)

          unless response.success?
            Log.error { "Registry API returned #{response.status_code}: #{response.status_message}" }
            raise RegistryError.new("Failed to fetch servers: #{response.status_code}")
          end

          registry_response = RegistryResponse.from_json(response.body)

          # Extract server info and mark official status
          registry_response.servers.each do |entry|
            server = entry.server
            if meta = entry._meta
              if official = meta["io.modelcontextprotocol.registry/official"]?
                server.is_official = official["status"]?.try(&.as_s) == "active"
                server.is_latest = official["isLatest"]?.try(&.as_bool) || false
              end
            end
            all_servers << server
          end

          # Check if there's a next page
          cursor = registry_response.metadata.next_cursor
          break if cursor.nil? || cursor.empty?
        end

        Log.info { "Fetched #{all_servers.size} servers from registry" }
        all_servers
      end

      # Generate config for installing a server
      def self.generate_config(server : ServerInfo) : Config::MCPServerConfig
        if server.needs_url?
          # URL-based server
          Config::MCPServerConfig.new(
            name: server.display_name,
            url: server.installation_target,
            landlock: suggest_landlock_restrictions(server)
          )
        elsif cmd = server.suggested_command
          # Command-based server
          Config::MCPServerConfig.new(
            name: server.display_name,
            command: cmd,
            landlock: suggest_landlock_restrictions(server)
          )
        else
          raise RegistryError.new("Cannot determine how to install server: #{server.name}")
        end
      end

      # Suggest Landlock restrictions based on server type
      private def self.suggest_landlock_restrictions(server : ServerInfo) : Config::MCPLandlockConfig?
        # Default restrictions for most servers
        allowed_paths = [] of String
        allowed_ports = [] of Int32

        # Analyze server description/type to suggest restrictions
        desc = server.description.downcase
        name = server.name.downcase

        # Web/API servers need network access
        if desc.includes?("web") || desc.includes?("api") || desc.includes?("http") ||
           name.includes?("exa") || name.includes?("search")
          # No additional filesystem access needed, default is fine
        end

        # Database servers might need data directory access
        if desc.includes?("database") || desc.includes?("storage")
          allowed_paths << "~/.crybot/data"
        end

        # Filesystem tools need user data access
        if desc.includes?("file") || desc.includes?("filesystem") || desc.includes?("storage")
          # Prompt user for paths instead of guessing
        end

        # If we have specific suggestions, return them
        if allowed_paths.any? || allowed_ports.any?
          Config::MCPLandlockConfig.new(
            allowed_paths: allowed_paths,
            allowed_ports: allowed_ports
          )
        else
          # nil means use default restrictions
          nil
        end
      end
    end

    class RegistryError < Exception
    end
  end
end
