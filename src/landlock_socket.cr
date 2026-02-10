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
      RequestAccess # Agent -> Monitor: Request access to a path
      Granted       # Monitor -> Agent: Access granted, will restart
      Denied        # Monitor -> Agent: Access denied
      Timeout       # Monitor -> Agent: Request timed out
    end

    struct AccessRequest
      property message_type : MessageType
      property path : String
      property response_channel : Channel(String)?

      def initialize(@path : String)
        @message_type = MessageType::RequestAccess
        @response_channel = Channel(String).new
      end
    end

    # Start the monitor server in the parent process
    def self.start_monitor_server : Nil
      # Remove socket file if it exists
      File.delete(socket_path) if File.exists?(socket_path)

      # Create Unix domain socket
      server = UNIXServer.new(socket_path)
      puts "[Monitor Socket] Listening on #{socket_path}"

      # Spawn a fiber to handle incoming connections
      spawn do
        loop do
          begin
            client = server.accept
            handle_client(client)
          rescue e : Exception
            STDERR.puts "[Monitor Socket] Error accepting connection: #{e.message}"
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
      path = request["path"]?.try(&.as_s)

      return unless message_type && path

      case message_type
      when "request_access"
        puts "[Monitor Socket] Access request for: #{path}"
        handle_access_request(client, path)
      else
        STDERR.puts "[Monitor Socket] Unknown message type: #{message_type}"
      end
    rescue e : Exception
      STDERR.puts "[Monitor Socket] Error handling client: #{e.message}"
    ensure
      client.close
    end

    private def self.handle_access_request(client : UNIXSocket, path : String) : Nil
      # Check if already allowed
      if already_allowed?(path)
        puts "[Monitor Socket] Path already allowed: #{path}"
        send_response(client, {"message_type" => "granted", "path" => path}.to_json)
        return
      end

      # Show prompt and get user decision
      response = prompt_user(path)

      case response
      when :granted
        add_permanent_access(path)
        puts "[Monitor Socket] Access granted for: #{path}"
        send_response(client, {"message_type" => "granted", "path" => path}.to_json)
      when :denied_suggest_playground
        puts "[Monitor Socket] Access denied, suggested playground for: #{path}"
        send_response(client, {"message_type" => "denied_suggest_playground", "path" => path}.to_json)
      when :denied
        puts "[Monitor Socket] Access denied for: #{path}"
        send_response(client, {"message_type" => "denied", "path" => path}.to_json)
      when :timeout
        puts "[Monitor Socket] Request timed out for: #{path}"
        send_response(client, {"message_type" => "timeout", "path" => path}.to_json)
      end
    end

    # Access response result
    enum AccessResult
      Granted
      Denied
      DeniedSuggestPlayground
      Timeout
    end

    def self.request_access(path : String, timeout : Time::Span = 5.minutes) : AccessResult
      # Connect to monitor socket
      client = UNIXSocket.new(socket_path)

      # Send request
      request = {
        "message_type" => "request_access",
        "path"         => path,
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

    private def self.send_response(client : UNIXSocket, json : String) : Nil
      client.puts(json)
      client.flush
    end

    private def self.already_allowed?(path : String) : Bool
      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      allowed_paths_file = File.join(monitor_dir, "allowed_paths.yml")

      return false unless File.exists?(allowed_paths_file)

      begin
        data = YAML.parse(File.read(allowed_paths_file))
        if data["paths"]?
          paths = data["paths"].as_a.map(&.as_s)
          # Expand ~ in stored paths
          paths.any? { |allowed_path| allowed_path == path || allowed_path == "~/#{File.basename(path)}" }
        else
          false
        end
      rescue e : Exception
        false
      end
    end

    private def self.add_permanent_access(path : String) : Nil
      # Use the pending access path if set (parent dir for files)
      actual_path = @@pending_access_path || path
      @@pending_access_path = nil # Reset after use

      puts "[LandlockSocket] add_permanent_access called with: #{path}"
      puts "[LandlockSocket] Using actual_path: #{actual_path}"

      home = ENV.fetch("HOME", "")
      monitor_dir = File.join(home, ".crybot", "monitor")
      Dir.mkdir_p(monitor_dir) unless Dir.exists?(monitor_dir)
      allowed_paths_file = File.join(monitor_dir, "allowed_paths.yml")

      # Load existing
      paths = if File.exists?(allowed_paths_file)
                data = YAML.parse(File.read(allowed_paths_file))
                if paths_arr = data["paths"]?.try(&.as_a)
                  paths_arr.map { |p| p.as_s.strip.gsub(/^'''|'''$/, "").gsub(/^'|'$/, "") }
                else
                  [] of String
                end
              else
                [] of String
              end

      # Add path if not already present
      paths << actual_path unless paths.includes?(actual_path)

      puts "[LandlockSocket] Final paths list: #{paths.inspect}"

      # Save - use simple YAML without extra quoting
      yaml_lines = ["---", "paths:"]
      paths.each do |p|
        yaml_lines << "  - \"#{p}\""
      end
      yaml_lines << "last_updated: \"#{Time.local.to_s}\""
      File.write(allowed_paths_file, yaml_lines.join("\n") + "\n")

      puts "[LandlockSocket] Added access to: #{actual_path}"
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
        "Allow",
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
      when "Allow"                           then :granted
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
      puts "  1) Allow"
      puts "  2) Deny - Suggest using playground"
      puts "  3) Deny"
      print "Choice [1-3]: "

      response = gets.try(&.strip) || ""

      case response
      when "1", "allow", "Allow"
        :granted
      when "2", "playground", "Deny - Suggest using playground"
        :denied_suggest_playground
      when "3", "deny", "Deny"
        :denied
      else
        :denied
      end
    end
  end
end
