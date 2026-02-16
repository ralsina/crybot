require "http"
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
    # Request and Response structures
    struct ProxyRequest
      property method : String
      property path : String
      property headers : Hash(String, String)
      property body : String?
      property domain : String?
      property query : String?

      def initialize(@method = "GET", @path = "/", @headers = {} of String => String, @body = nil, @domain = nil, @query = nil)
      end
    end

    # Access log entry
    struct AccessLog
      property timestamp : String
      property domain : String
      property action : String
      property details : String?

      def initialize(@timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S"), @domain = "", @action = "", @details = "")
      end
    end

    @@config : Crybot::Config::ProxyConfig?
    @@access_log : Array(AccessLog) = [] of AccessLog
    @@server : HTTP::Server?

    def self.start : Nil
      config = Crybot::Config::Loader.load
      proxy_config = config.proxy

      unless proxy_config.enabled
        Log.info { "HTTP proxy not enabled in config, skipping startup" }
        return
      end

      @@config = proxy_config
      @@access_log = [] of AccessLog

      # Create HTTP server with handler proc
      server = HTTP::Server.new do |context|
        handle_request(context, proxy_config)
      end

      @@server = server

      # Start listening in background
      spawn do
        server.bind_tcp(proxy_config.host, proxy_config.port)
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

    # Handle incoming HTTP request
    private def self.handle_request(context : HTTP::Server::Context, config : Crybot::Config::ProxyConfig) : Nil
      request = parse_request(context)

      # Extract domain from request
      request_domain = extract_domain(request)

      # Check whitelist
      if config.domain_whitelist.includes?(request_domain)
        # Whitelisted domain - allow through
        log_access(request_domain, "allow", "Whitelisted")
        forward_request(context, request)
      else
        # Non-whitelisted domain - prompt user
        prompt_user_and_handle(context, request, request_domain, config)
      end
    end

    # Parse HTTP request from context
    private def self.parse_request(context : HTTP::Server::Context) : ProxyRequest
      method = context.request.method || "GET"
      full_path = context.request.path || "/"

      # Split path and query string
      parts = full_path.split('?', 2)
      path = parts[0]?
      query = parts[1]?

      # Normalize headers to Hash(String, String)
      raw_headers = context.request.headers.try(&.to_h) || {} of String => String | Array(String)
      headers = {} of String => String
      raw_headers.each do |key, value|
        headers[key] = value.is_a?(Array) ? value.first.to_s : value.to_s
      end

      body = if body_io = context.request.body
               body_io.gets_to_end
             else
               nil
             end

      # Extract Host header for domain checking
      domain = if host_header = headers["Host"]?
                 URI.parse(host_header).hostname
               else
                 nil
               end

      ProxyRequest.new(method, path || "/", headers, body, domain, query)
    end

    # Extract domain from Host header or URL path
    private def self.extract_domain(request : ProxyRequest) : String
      # Check Host header first
      if domain = request.domain
        return domain
      end

      # Try to extract from request path if it's a full URL
      # When using curl -x, the path is like "https://example.com/" or "http://example.com/"
      path = request.path
      if path.size > 1
        # Check if path looks like a URL (starts with http:// or https://)
        if path =~ %r{^https?://}
          begin
            uri = URI.parse(path)
            if hostname = uri.hostname
              return hostname
            end
          rescue
            # If URI parsing fails, try to extract domain manually
            # Remove scheme and path, keep domain
            if match = path.match(%r{^https?://([^/:]+)})
              return match[1]
            end
          end
        end
      end

      ""
    end

    # Log access attempt
    private def self.log_access(domain : String, action : String, details : String = "") : Nil
      log_entry = AccessLog.new(domain, action, details)

      @@access_log << log_entry
      Log.info { "[#{log_entry.action}] #{log_entry.domain}: #{log_entry.details}" }

      # Also write to file if configured
      if cfg = @@config
        begin
          # Expand ~ in log file path
          log_path = cfg.log_file.starts_with?("~") ? cfg.log_file.sub("~", ENV.fetch("HOME", "")) : cfg.log_file

          # Ensure log directory exists
          log_dir = File.dirname(log_path)
          Dir.mkdir_p(log_dir) unless Dir.exists?(log_dir)

          File.open(log_path, "a") do |file|
            @@access_log.each do |entry|
              file.puts("#{entry.timestamp} #{entry.action} #{entry.domain} - #{entry.details}")
            end
          end
        rescue e : Exception
          Log.error(exception: e) { "Failed to write access log: #{e.message}" }
        end
      end
    end

    # Prompt user via unified IPC and handle decision
    private def self.prompt_user_and_handle(context : HTTP::Server::Context, request : ProxyRequest, request_domain : String, config : Crybot::Config::ProxyConfig) : Nil
      # Use unified LandlockSocket for network access requests
      result = Crybot::LandlockSocket.request_network_access(request_domain)

      case result
      when Crybot::LandlockSocket::AccessResult::Granted
        # Whitelisted - allow through and log
        log_access(request_domain, "allow", "Whitelisted")
        forward_request(context, request)
      when Crybot::LandlockSocket::AccessResult::GrantedOnce
        # Allow once - allow through but don't save to whitelist
        log_access(request_domain, "allow_once", "Session-only allowance")
        forward_request(context, request)
      when Crybot::LandlockSocket::AccessResult::Denied
        # Denied - return 403
        log_access(request_domain, "deny", "User denied")
        context.response.status_code = 403
        context.response.puts("Access denied")
        context.response.close
      else
        # Unexpected response (timeout, etc.) - log and deny
        log_access(request_domain, "deny", "Invalid response (#{result})")
        context.response.status_code = 403
        context.response.puts("Access denied")
        context.response.close
      end
    end

    # Forward request to upstream
    private def self.forward_request(context : HTTP::Server::Context, request : ProxyRequest) : Nil
      # Domain is required
      domain = request.domain
      return unless domain

      # Extract the actual path from the request
      # When using curl -x, the path might be a full URL like "https://example.com/"
      # We need to extract just the path component
      upstream_path = request.path

      # If path looks like a full URL, extract just the path part
      if upstream_path =~ %r{^https?://}
        begin
          uri = URI.parse(upstream_path)
          upstream_path = uri.path || "/"
          # Add back query string if present in URI
          if uri.query && !request.query
            upstream_path = "#{upstream_path}?#{uri.query}"
          end
        rescue
          # If URI parsing fails, just use the path as-is
        end
      end

      # Add query string if present and not already in path
      if query = request.query
        unless upstream_path.includes?("?")
          upstream_path = "#{upstream_path}?#{query}"
        end
      end

      # Create upstream request
      begin
        # Convert headers to HTTP::Headers
        http_headers = HTTP::Headers.new
        request.headers.each do |key, value|
          # Skip proxy-related headers that shouldn't be forwarded
          http_headers[key] = value unless key.downcase == "proxy-connection"
        end

        # Use HTTP::Client to forward the request
        client = HTTP::Client.new(domain)
        response = client.exec(request.method, upstream_path, http_headers, request.body)

        # Copy response headers to client response
        response.headers.each do |key, value|
          context.response.headers[key] = value
        end

        # Copy response body
        context.response.puts(response.body)
        context.response.close

        Log.debug { "Forwarded: #{request.method} #{upstream_path} -> #{domain} (#{response.status_code})" }
      rescue e : Exception
        Log.error(exception: e) { "Proxy error: #{e.message}" }
        context.response.status_code = 500
        context.response.puts("Proxy error: #{e.message}")
        context.response.close
      end
    end
  end
end
