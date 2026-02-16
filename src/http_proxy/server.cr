require "http_proxy"
require "log"
require "../config/loader"
require "../landlock_socket"

module HttpProxy
  Log = ::Log.for("crybot.http_proxy")

  # HTTP/HTTPS proxy server for tool access control
  #
  # Listens on localhost:3004
  # Checks domain whitelist
  # Prompts user via rofi for non-whitelisted domains
  # Forwards allowed requests to upstream
  # Logs all access attempts

  class Server
    # Access log entry
    struct AccessLog
      property timestamp : String
      property domain : String
      property action : String
      property details : String?

      def initialize(@timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S"), @domain = "", @action = "", @details = "")
      end
    end

    # Custom handler for access control
    class AccessControlHandler
      include HTTP::Handler

      def initialize(@config : Crybot::Config::ProxyConfig)
      end

      def call(context)
        request = context.request

        # Extract domain from request
        domain = extract_domain(request)
        Log.info { "[Proxy] Extracted domain: #{domain.inspect}" }

        # Check if domain is empty
        if domain.empty?
          Log.warn { "Could not extract domain from request" }
          context.response.status_code = 400
          context.response.puts("Bad Request: Could not determine domain")
          return
        end

        # Handle CONNECT method for HTTPS (tunneling)
        if request.method == "CONNECT"
          handle_connect(context, domain)
          return
        end

        # Handle regular HTTP request
        handle_http_request(context, request, domain)
      end

      private def extract_domain(request : HTTP::Request) : String
        # Check Host header first
        if host_header = request.headers["Host"]?
          begin
            uri = URI.parse("http://#{host_header}")
            if hostname = uri.hostname
              return hostname
            end
          rescue
            # If URI parsing fails, extract hostname manually
            if match = host_header.match(/^([^:]+)/)
              return match[1]
            end
          end
        end

        # For CONNECT method, resource contains "host:port"
        if request.method == "CONNECT"
          resource = request.resource
          if idx = resource.index(':')
            return resource[0...idx]
          end
        end

        ""
      end

      private def handle_connect(context : HTTP::Server::Context, domain : String)
        config = @config

        # Check whitelist
        if config.domain_whitelist.includes?(domain)
          log_access(domain, "connect", "Whitelisted HTTPS tunnel")
          # Let the proxy handler handle the tunneling
          call_next(context)
        else
          prompt_user_and_handle_connect(context, domain, config)
        end
      end

      private def handle_http_request(context : HTTP::Server::Context, request : HTTP::Request, domain : String)
        config = @config

        # Check whitelist
        if config.domain_whitelist.includes?(domain)
          log_access(domain, "allow", "Whitelisted")
          call_next(context)
        else
          prompt_user_and_handle(context, request, domain, config)
        end
      end

      private def prompt_user_and_handle_connect(context : HTTP::Server::Context, domain : String, config : Crybot::Config::ProxyConfig)
        result = Crybot::LandlockSocket.request_network_access(domain)

        case result
        when Crybot::LandlockSocket::AccessResult::Granted
          log_access(domain, "connect", "Allowed HTTPS tunnel")
          call_next(context)
        when Crybot::LandlockSocket::AccessResult::GrantedOnce
          log_access(domain, "connect_once", "Session-only HTTPS tunnel")
          call_next(context)
        when Crybot::LandlockSocket::AccessResult::Denied
          log_access(domain, "connect_deny", "User denied HTTPS tunnel")
          context.response.status_code = 403
          context.response.puts("Access denied")
        else
          log_access(domain, "connect_deny", "Invalid response (#{result})")
          context.response.status_code = 403
          context.response.puts("Access denied")
        end
      end

      private def prompt_user_and_handle(context : HTTP::Server::Context, request : HTTP::Request, domain : String, config : Crybot::Config::ProxyConfig)
        result = Crybot::LandlockSocket.request_network_access(domain)

        case result
        when Crybot::LandlockSocket::AccessResult::Granted
          log_access(domain, "allow", "Whitelisted")
          call_next(context)
        when Crybot::LandlockSocket::AccessResult::GrantedOnce
          log_access(domain, "allow_once", "Session-only allowance")
          call_next(context)
        when Crybot::LandlockSocket::AccessResult::Denied
          log_access(domain, "deny", "User denied")
          context.response.status_code = 403
          context.response.puts("Access denied")
        else
          log_access(domain, "deny", "Invalid response (#{result})")
          context.response.status_code = 403
          context.response.puts("Access denied")
        end
      end

      private def log_access(domain : String, action : String, details : String = "")
        log_entry = AccessLog.new(domain, action, details)

        Server.log_access(log_entry)

        Log.info { "[#{log_entry.action}] #{log_entry.domain}: #{log_entry.details}" }
      end
    end

    @@config : Crybot::Config::ProxyConfig?
    @@access_log : Array(AccessLog) = [] of AccessLog
    @@server : ::HTTP::Proxy::Server?

    def self.start : Nil
      config = Crybot::Config::Loader.load
      proxy_config = config.proxy

      unless proxy_config.enabled
        Log.info { "HTTP proxy not enabled in config, skipping startup" }
        return
      end

      @@config = proxy_config
      @@access_log = [] of AccessLog

      # Create HTTP proxy server with access control handler
      access_handler = AccessControlHandler.new(proxy_config)

      server = ::HTTP::Proxy::Server.new(handlers: [access_handler])

      @@server = server

      # Start listening in background
      spawn do
        address = server.bind_tcp(proxy_config.host, proxy_config.port)
        Log.info { "Proxy server bound to #{address}" }
        server.listen
      rescue e : Exception
        Log.error(exception: e) { "Proxy server error: #{e.message}" }
      end

      # Give the server a moment to start
      sleep 0.1

      Log.info { "Proxy server started on http://#{proxy_config.host}:#{proxy_config.port}" }
      Log.info { "Domain whitelist: #{proxy_config.domain_whitelist.join(", ")}" }
      Log.info { "Access log: #{proxy_config.log_file}" }
    end

    def self.stop : Nil
      if server = @@server
        server.close
        Log.info { "Proxy server stopped" }
      end
    end

    # Log access attempt (called from AccessControlHandler)
    def self.log_access(entry : AccessLog)
      @@access_log << entry

      # Also write to file if configured
      if cfg = @@config
        begin
          # Expand ~ in log file path
          log_path = cfg.log_file.starts_with?("~") ? cfg.log_file.sub("~", ENV.fetch("HOME", "")) : cfg.log_file

          # Ensure log directory exists
          log_dir = File.dirname(log_path)
          Dir.mkdir_p(log_dir) unless Dir.exists?(log_dir)

          File.open(log_path, "a") do |file|
            file.puts("#{entry.timestamp} #{entry.action} #{entry.domain} - #{entry.details}")
          end
        rescue e : Exception
          Log.error(exception: e) { "Failed to write access log: #{e.message}" }
        end
      end
    end
  end
end
