require "log"
require "socket"
require "json"
require "yaml"

module Crybot
  module LandlockSocket
    # Socket path for IPC
    def self.socket_path : String
      home = ENV.fetch("HOME", "")
      File.join(home, ".crybot", "landlock.sock")
    end

    # Stores the actual path to grant access to (parent dir for files)
    @@pending_access_path : String?

    # Message types
    enum MessageType
      RequestAccess        # Agent -> Monitor: Request access to a path
      RequestNetworkAccess # Agent -> Monitor: Request access to a domain
      Granted              # Monitor -> Agent: Access granted, will restart
      Denied               # Monitor -> Agent: Access denied
      Timeout              # Monitor -> Agent: Request timed out
    end

    struct AccessRequest
      property message_type : MessageType
      property path : String
      property session_id : String?
      property response_channel : Channel(String)?

      def initialize(@path : String, @session_id : String? = nil)
        @message_type = MessageType::RequestAccess
        @response_channel = Channel(String).new
      end
    end

    struct NetworkAccessRequest
      property message_type : MessageType
      property domain : String
      property response_channel : Channel(String)?

      def initialize(@domain : String)
        @message_type = MessageType::RequestNetworkAccess
        @response_channel = Channel(String).new
      end
    end

    # Start the monitor server in the parent process
    def self.start_monitor_server : Nil
      # Remove socket file if it exists
      File.delete(socket_path) if File.exists?(socket_path)

      # Create Unix domain socket
      server = UNIXServer.new(socket_path)
      Log.info { "[Monitor Socket] Listening on #{socket_path}" }

      # Spawn a fiber to handle incoming connections
      spawn do
        loop do
          begin
            client = server.accept
            handle_client(client)
          rescue e : Exception
            Log.error(exception: e) { "[Monitor Socket] Error accepting connection: #{e.message}" }
          end
        end
      end
    end

    private def self.handle_client(client : UNIXSocket) : Nil
      # Receive request from agent
      request_data = client.gets
      return unless request_data

      request = JSON.parse(request_data) rescue nil
      return unless request

      message_type = request["message_type"]?.try(&.as_s)

      case message_type
      when "request_access"
        path = request["path"]?.try(&.as_s)
        if path
          Log.info { "[Monitor Socket] Path access request for: #{path}" }
          handle_access_request(client, path)
        end
      when "request_network_access"
        domain = request["domain"]?.try(&.as_s)
        if domain
          Log.info { "[Monitor Socket] Network access request for: #{domain}" }
          handle_network_access_request(client, domain)
        end
      else
        Log.warn { "[Monitor Socket] Unknown message type: #{message_type}" }
      end
    rescue e : Exception
      Log.error(exception: e) { "[Monitor Socket] Error handling client: #{e.message}" }
    ensure
      client.close
    end

    private def self.handle_access_request(client : UNIXSocket, path : String) : Nil
      # Get session_id from request
      # We'll get it from the request JSON

      # Check if already allowed
      if already_allowed?(path)
        Log.info { "[Monitor Socket] Path already allowed: #{path}" }
        send_response(client, {"message_type" => "granted", "path" => path}.to_json)
        return
      end

      # Show prompt and get user decision
      response = prompt_user(path)

      case response
      when :granted
        add_permanent_access(path)
        Log.info { "[Monitor Socket] Access granted for: #{path}" }
        send_response(client, {"message_type" => "granted", "path" => path}.to_json)
      when :granted_session
        add_session_access(path, current_session_id)
        Log.info { "[Monitor Socket] Access granted for session: #{path}" }
        send_response(client, {"message_type" => "granted_session", "path" => path}.to_json)
      when :granted_once
        Log.info { "[Monitor Socket] Access granted once for: #{path}" }
        send_response(client, {"message_type" => "granted_once", "path" => path}.to_json)
      when :denied_suggest_playground
        Log.info { "[Monitor Socket] Access denied, suggested playground for: #{path}" }
        send_response(client, {"message_type" => "denied_suggest_playground", "path" => path}.to_json)
      when :denied
        Log.info { "[Monitor Socket] Access denied for: #{path}" }
        send_response(client, {"message_type" => "denied", "path" => path}.to_json)
      when :timeout
        Log.info { "[Monitor Socket] Request timed out for: #{path}" }
        send_response(client, {"message_type" => "timeout", "path" => path}.to_json)
      end
    end

    # Handle network access request
    private def self.handle_network_access_request(client : UNIXSocket, domain : String) : Nil
      # Check if already whitelisted
      if domain_whitelisted?(domain)
        Log.info { "[Monitor Socket] Domain already whitelisted: #{domain}" }
        send_response(client, {"message_type" => "granted", "domain" => domain}.to_json)
        return
      end

      # Show prompt and get user decision
      response = prompt_user_for_domain(domain)

      case response
      when :granted
        add_domain_to_whitelist(domain)
        Log.info { "[Monitor Socket] Domain access granted for: #{domain}" }
        send_response(client, {"message_type" => "granted", "domain" => domain}.to_json)
      when :granted_once
        Log.info { "[Monitor Socket] Domain access granted once for: #{domain}" }
        send_response(client, {"message_type" => "granted_once", "domain" => domain}.to_json)
      when :denied
        Log.info { "[Monitor Socket] Domain access denied for: #{domain}" }
        send_response(client, {"message_type" => "denied", "domain" => domain}.to_json)
      when :timeout
        Log.info { "[Monitor Socket] Domain request timed out for: #{domain}" }
        send_response(client, {"message_type" => "timeout", "domain" => domain}.to_json)
      end
    end

    # Access response result
    enum AccessResult
      Granted        # Permanent access
      GrantedSession # Session-scoped access
      GrantedOnce    # Single-use access
      Denied
      DeniedSuggestPlayground
      Timeout
    end

    def self.request_access(path : String, session_id : String? = nil, timeout : Time::Span = 5.minutes) : AccessResult
      # Connect to monitor socket
      client = UNIXSocket.new(socket_path)

      # Send request
      request = {
        "message_type" => "request_access",
        "path"         => path,
        "session_id"   => session_id,
      }.to_json

      client.puts(request)

      # Receive response (with timeout using channel)
      response_channel = Channel(String?).new

      # Spawn fiber to read response
      spawn do
        begin
          response = client.gets
          response_channel.send(response)
        rescue e : Exception
          response_channel.send(nil)
        ensure
          client.close
        end
      end

      # Spawn fiber for timeout
      timeout_channel = Channel(Nil).new
      spawn do
        sleep timeout
        timeout_channel.send(nil)
      end

      # Wait for either response or timeout
      select
      when r = response_channel.receive
        # Parse response
        return AccessResult::Timeout unless r

        parsed = JSON.parse(r) rescue nil
        return AccessResult::Timeout unless parsed
      when timeout_channel.receive
        # Timeout occurred
        client.close rescue nil
        return AccessResult::Timeout
      end

      message_type = parsed["message_type"]?.try(&.as_s)

      case message_type
      when "granted"
        AccessResult::Granted
      when "granted_session"
        AccessResult::GrantedSession
      when "granted_once"
        AccessResult::GrantedOnce
      when "denied"
        AccessResult::Denied
      when "denied_suggest_playground"
        AccessResult::DeniedSuggestPlayground
      when "timeout"
        AccessResult::Timeout
      else
        AccessResult::Denied
      end
    end

    def self.request_network_access(domain : String, timeout : Time::Span = 5.minutes) : AccessResult
      # Connect to monitor socket
      client = UNIXSocket.new(socket_path)

      # Send request
      request = {
        "message_type" => "request_network_access",
        "domain"       => domain,
      }.to_json

      client.puts(request)

      # Receive response (with timeout using channel)
      response_channel = Channel(String?).new

      # Spawn fiber to read response
      spawn do
        begin
          response = client.gets
          response_channel.send(response)
        rescue e : Exception
          response_channel.send(nil)
        ensure
          client.close
        end
      end

      # Spawn fiber for timeout
      timeout_channel = Channel(Nil).new
      spawn do
        sleep timeout
        timeout_channel.send(nil)
      end

      # Wait for either response or timeout
      select
      when r = response_channel.receive
        # Parse response
        return AccessResult::Timeout unless r

        parsed = JSON.parse(r) rescue nil
        return AccessResult::Timeout unless parsed
      when timeout_channel.receive
        # Timeout occurred
        client.close rescue nil
        return AccessResult::Timeout
      end

      message_type = parsed["message_type"]?.try(&.as_s)

      case message_type
      when "granted"
        AccessResult::Granted
      when "granted_once"
        AccessResult::GrantedOnce
      when "denied"
        AccessResult::Denied
      when "timeout"
        AccessResult::Timeout
      else
        AccessResult::Denied
      end
    end

    private def self.send_response(client : UNIXSocket, json : String) : Nil
      client.puts(json)
      client.flush
    end

    private def self.already_allowed?(path : String) : Bool
      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      allowed_paths_file = File.join(monitor_dir, "allowed_paths.yml")

      # Check permanent permissions
      if File.exists?(allowed_paths_file)
        begin
          data = YAML.parse(File.read(allowed_paths_file))
          if data["paths"]?
            paths = data["paths"].as_a.map(&.as_s)
            # Expand ~ in stored paths
            if paths.any? { |allowed_path| allowed_path == path || allowed_path == "~/#{File.basename(path)}" }
              return true
            end
          end
        rescue e : Exception
          # Continue to session check
        end
      end

      # Check session permissions
      session_id = current_session_id
      if session_id && session_allowed?(path, session_id)
        return true
      end

      false
    end

    private def self.add_permanent_access(path : String) : Nil
      # Use the pending access path if set (parent dir for files)
      actual_path = @@pending_access_path || path
      @@pending_access_path = nil # Reset after use

      Log.debug { "[LandlockSocket] add_permanent_access called with: #{path}" }
      Log.debug { "[LandlockSocket] Using actual_path: #{actual_path}" }

      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      Dir.mkdir_p(monitor_dir) unless Dir.exists?(monitor_dir)
      allowed_paths_file = File.join(monitor_dir, "allowed_paths.yml")

      # Load existing
      paths = if File.exists?(allowed_paths_file)
                data = YAML.parse(File.read(allowed_paths_file))
                if paths_arr = data["paths"]?.try(&.as_a)
                  paths_arr.map { |path_| path_.as_s.strip.gsub(/^'''|'''$/, "").gsub(/^'|'$/, "") }
                else
                  [] of String
                end
              else
                [] of String
              end

      # Add path if not already present
      paths << actual_path unless paths.includes?(actual_path)

      Log.debug { "[LandlockSocket] Final paths list: #{paths.inspect}" }

      # Save - use simple YAML without extra quoting
      yaml_lines = ["---", "paths:"]
      paths.each do |path_|
        yaml_lines << "  - \"#{path_}\""
      end
      yaml_lines << "last_updated: \"#{Time.local}\""
      File.write(allowed_paths_file, yaml_lines.join("\n") + "\n")

      Log.info { "[LandlockSocket] Added permanent access to: #{actual_path}" }
    end

    # Get current session_id from Agent module's session store
    private def self.current_session_id : String?
      # This is set by the agent loop before calling tools
      Crybot::Agent.current_session
    end

    # Add session-scoped access
    private def self.add_session_access(path : String, session_id : String?) : Nil
      return unless session_id

      # Use the pending access path if set (parent dir for files)
      actual_path = @@pending_access_path || path
      @@pending_access_path = nil # Reset after use

      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      Dir.mkdir_p(monitor_dir) unless Dir.exists?(monitor_dir)
      sessions_file = File.join(monitor_dir, "session_permissions.yml")

      # Load existing sessions
      sessions = if File.exists?(sessions_file)
                   data = YAML.parse(File.read(sessions_file))
                   if sessions_hash = data["sessions"]?.try(&.as_h)
                     # Convert YAML::Any keys to String
                     result = {} of String => Array(String)
                     sessions_hash.each do |k, v|
                       sess_id = k.as_s
                       paths = v.as_a.map(&.as_s)
                       result[sess_id] = paths
                     end
                     result
                   else
                     {} of String => Array(String)
                   end
                 else
                   {} of String => Array(String)
                 end

      # Add path to this session
      sessions[session_id] ||= [] of String
      sessions[session_id] << actual_path unless sessions[session_id].includes?(actual_path)

      # Save with timestamp
      yaml_lines = ["---", "sessions:"]
      sessions.each do |sess_id, paths|
        yaml_lines << "  \"#{sess_id}\":"
        paths.each do |path_|
          yaml_lines << "    - \"#{path_}\""
        end
      end
      yaml_lines << "last_updated: \"#{Time.local}\""
      File.write(sessions_file, yaml_lines.join("\n") + "\n")

      Log.info { "[LandlockSocket] Added session access to: #{actual_path} for session: #{session_id}" }
    end

    # Check if path is allowed for current session
    private def self.session_allowed?(path : String, session_id : String?) : Bool
      return false unless session_id

      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      sessions_file = File.join(monitor_dir, "session_permissions.yml")

      return false unless File.exists?(sessions_file)

      begin
        data = YAML.parse(File.read(sessions_file))
        if sessions_hash = data["sessions"]?.try(&.as_h)
          session_paths = sessions_hash[session_id]?.try(&.as_a.map(&.as_s))
          if session_paths
            # Check if path or any parent is in session permissions
            session_paths.any? { |allowed_path| path.starts_with?(allowed_path) }
          else
            false
          end
        else
          false
        end
      rescue e : Exception
        Log.debug { "[LandlockSocket] Error checking session permissions: #{e.message}" }
        false
      end
    end

    # Clean up expired session permissions (call this periodically or on session end)
    def self.cleanup_expired_sessions(active_sessions : Array(String)) : Nil
      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      sessions_file = File.join(monitor_dir, "session_permissions.yml")

      return unless File.exists?(sessions_file)

      begin
        data = YAML.parse(File.read(sessions_file))
        if sessions_hash = data["sessions"]?.try(&.as_h)
          # Remove sessions not in active_sessions list
          sessions_hash = sessions_hash.transform_values(&.as_a.map(&.as_s))
          active_hash = sessions_hash.select { |sess_id, _paths| active_sessions.includes?(sess_id) }

          if active_hash.empty?
            # No active sessions, remove file
            File.delete(sessions_file) if File.exists?(sessions_file)
          else
            yaml_lines = ["---", "sessions:"]
            active_hash.each do |sess_id, paths|
              yaml_lines << "  \"#{sess_id}\":"
              paths.each do |path|
                yaml_lines << "    - \"#{path}\""
              end
            end
            yaml_lines << "last_updated: \"#{Time.local}\""
            File.write(sessions_file, yaml_lines.join("\n") + "\n")
          end

          Log.info { "[LandlockSocket] Cleaned up expired sessions" }
        end
      rescue e : Exception
        Log.error(exception: e) { "[LandlockSocket] Error cleaning up sessions: #{e.message}" }
      end
    end

    # Prompt user for access (rofi or terminal)
    private def self.prompt_user(path : String) : Symbol
      home = ENV.fetch("HOME", "")
      display_path = path.starts_with?(home) ? path.sub(home, "~") : path

      # For files (existing or not), we grant access to the parent directory
      # This allows creating new files and avoids issues with non-existent paths
      target_path = path
      parent_note = ""

      if !Dir.exists?(path)
        parent = File.dirname(path)
        parent_display = parent.starts_with?(home) ? parent.sub(home, "~") : parent
        target_path = parent
        parent_note = " (grants RW access to: #{parent_display})"
      end

      # Store the actual path we'll grant access to (may be parent dir)
      # This is used by add_permanent_access
      @@pending_access_path = target_path

      # Check for graphical environment
      has_display = ENV.has_key?("DISPLAY") || ENV.has_key?("WAYLAND_DISPLAY")

      if has_display && Process.find_executable("rofi")
        result = prompt_with_rofi(display_path, parent_note)
        return result if result
      end

      # Fall back to terminal prompt
      prompt_with_terminal(display_path, parent_note)
    end

    # Prompt using rofi
    private def self.prompt_with_rofi(path : String, parent_note : String) : Symbol?
      prompt = "Allow access?"
      message = "🔒 Agent requests: #{path}#{parent_note}"

      options = [
        "Always",
        "This Session",
        "Once",
        "Deny - Suggest using playground",
        "Deny",
      ]

      menu_text = options.join("\n")
      result = IO::Memory.new

      status = Process.run(
        "rofi",
        [
          "-dmenu",
          "-p", prompt,
          "-mesg", message,
          "-i",
          "-lines", "4",
          "-width", "60",
          "-location", "1",
        ],
        input: IO::Memory.new(menu_text),
        output: result
      )

      return nil unless status.success?

      selection = result.to_s.strip
      case selection
      when "Always"                          then :granted
      when "This Session"                    then :granted_session
      when "Once"                            then :granted_once
      when "Deny - Suggest using playground" then :denied_suggest_playground
      when "Deny"                            then :denied
      else                                        nil
      end
    rescue e : Exception
      nil
    end

    # Prompt using terminal
    private def self.prompt_with_terminal(path : String, parent_note : String) : Symbol
      puts "\n" + "=" * 60
      puts "🔒 Landlock Access Request"
      puts "=" * 60
      puts "The agent wants to access: #{path}#{parent_note}"
      puts ""
      puts "Options:"
      puts "  1) Always"
      puts "  2) This Session"
      puts "  3) Once"
      puts "  4) Deny - Suggest using playground"
      puts "  5) Deny"
      print "Choice [1-5]: "

      response = gets.try(&.strip) || ""

      case response
      when "1", "always", "Always"
        :granted
      when "2", "session", "This Session"
        :granted_session
      when "3", "once", "Once"
        :granted_once
      when "4", "playground", "Deny - Suggest using playground"
        :denied_suggest_playground
      when "5", "deny", "Deny"
        :denied
      else
        :denied
      end
    end

    # Check if domain is already whitelisted
    private def self.domain_whitelisted?(domain : String) : Bool
      config = Crybot::Config::Loader.load
      config.proxy.domain_whitelist.includes?(domain)
    rescue
      false
    end

    # Add domain to whitelist
    private def self.add_domain_to_whitelist(domain : String) : Nil
      config = Crybot::Config::Loader.load
      proxy_config = config.proxy
      whitelist = proxy_config.domain_whitelist.dup

      return if whitelist.includes?(domain)

      whitelist << domain

      # Update config with new whitelist
      updated_proxy = Crybot::Config::ProxyConfig.new(
        enabled: proxy_config.enabled?,
        host: proxy_config.host,
        port: proxy_config.port,
        domain_whitelist: whitelist,
        log_file: proxy_config.log_file
      )

      # Update the full config
      updated_config = config
      updated_config.proxy = updated_proxy

      # Write updated config to file
      config_path = Crybot::Config::Loader.config_file
      File.write(config_path, updated_config.to_yaml)

      # Reload config
      Crybot::Config::Loader.reload

      Log.info { "[LandlockSocket] Added domain to whitelist: #{domain}" }
    rescue e : Exception
      Log.error(exception: e) { "[LandlockSocket] Failed to add domain to whitelist: #{e.message}" }
    end

    # Prompt user for domain access (rofi or terminal)
    private def self.prompt_user_for_domain(domain : String) : Symbol
      # Check for graphical environment
      has_display = ENV.has_key?("DISPLAY") || ENV.has_key?("WAYLAND_DISPLAY")

      if has_display && Process.find_executable("rofi")
        result = prompt_domain_with_rofi(domain)
        return result if result
      end

      # Fall back to terminal prompt
      prompt_domain_with_terminal(domain)
    end

    # Prompt using rofi for domain access
    private def self.prompt_domain_with_rofi(domain : String) : Symbol?
      prompt = "Allow domain?"
      message = "🔒 Agent requests network access to: #{domain}"

      options = [
        "Allow",
        "Once Only",
        "Deny",
      ]

      menu_text = options.join("\n")
      result = IO::Memory.new

      status = Process.run(
        "rofi",
        [
          "-dmenu",
          "-p", prompt,
          "-mesg", message,
          "-i",
          "-lines", "3",
          "-width", "60",
          "-location", "1",
        ],
        input: IO::Memory.new(menu_text),
        output: result
      )

      return nil unless status.success?

      selection = result.to_s.strip
      case selection
      when "Allow"     then :granted
      when "Once Only" then :granted_once
      when "Deny"      then :denied
      else                  nil
      end
    rescue e : Exception
      nil
    end

    # Prompt using terminal for domain access
    private def self.prompt_domain_with_terminal(domain : String) : Symbol
      puts "\n" + "=" * 60
      puts "🔒 Network Access Request"
      puts "=" * 60
      puts "The agent wants to connect to: #{domain}"
      puts ""
      puts "Options:"
      puts "  1) Allow"
      puts "  2) Once Only"
      puts "  3) Deny"
      print "Choice [1-3]: "

      response = gets.try(&.strip) || ""

      case response
      when "1", "allow", "Allow"
        :granted
      when "2", "once", "Once Only"
        :granted_once
      when "3", "deny", "Deny"
        :denied
      else
        :denied
      end
    end
  end
end
