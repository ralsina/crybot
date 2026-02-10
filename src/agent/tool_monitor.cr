require "json"
require "tool_runner"
require "./tools/registry"
require "./tools/filesystem"
require "./tools/shell"
require "./tools/memory"
require "./tools/web"
require "./tools/skill_builder"
require "./tools/web_scraper_skill"
require "../landlock_socket"

module Crybot
  module Agent
    # Tool Monitor - Manages tool execution in Landlocked contexts
    #
    # Uses ToolRunner library to execute tools in isolated threads with Landlock.
    module ToolMonitor
      # Request from agent
      struct ToolRequest
        property tool_name : String
        property arguments : Hash(String, JSON::Any)
        property response_channel : Channel(ToolResponse)

        def initialize(@tool_name : String, @arguments : Hash(String, JSON::Any), @response_channel : Channel(ToolResponse))
        end
      end

      # Response from monitor
      # ameba:disable Naming/QueryBoolMethods
      struct ToolResponse
        property success : Bool
        property result : String

        def initialize(@success : Bool, @result : String)
        end
      end

      @@request_channel : Channel(ToolRequest)?

      def self.request_channel : Channel(ToolRequest)
        @@request_channel ||= Channel(ToolRequest).new
      end

      # Start the monitor fiber
      def self.start_monitor : Fiber
        spawn do
          monitor_loop
        end
      end

      # Monitor loop - runs in a fiber, handles tool execution requests
      private def self.monitor_loop : Nil
        puts "[ToolMonitor] Starting monitor fiber..."

        loop do
          begin
            request = request_channel.receive

            # Check if this is an MCP tool (contains / separator)
            # MCP tools must execute in the main process to access the MCP client
            if request.tool_name.includes?("/")
              result = execute_directly(request.tool_name, request.arguments)
            else
              result = execute_with_landlock(request.tool_name, request.arguments)
            end

            response = ToolResponse.new(true, result)
            request.response_channel.send(response)
          rescue e : Exception
            STDERR.puts "[ToolMonitor] Error: #{e.message}"
            STDERR.puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end
      end

      # Execute tool directly in the main process (for MCP tools)
      private def self.execute_directly(tool_name : String, arguments : Hash(String, JSON::Any)) : String
        tool = Tools::Registry.get(tool_name)
        return "Error: Tool '#{tool_name}' not found" if tool.nil?

        begin
          tool.execute(arguments)
        rescue e : Exception
          "Error: #{e.message}"
        end
      end

      # Execute a tool through the monitor (called from agent/tools)
      def self.execute_tool(tool_name : String, arguments : Hash(String, JSON::Any)) : String
        response_channel = Channel(ToolResponse).new
        request = ToolRequest.new(tool_name, arguments, response_channel)

        request_channel.send(request)

        response = response_channel.receive
        response.result
      end

      # Execute tool with Landlock using ToolRunner library
      private def self.execute_with_landlock(tool_name : String, arguments : Hash(String, JSON::Any)) : String
        # Get default restrictions from ToolRunner
        restrictions = ::ToolRunner::Landlock::Restrictions.default_crybot

        # Add any user-configured allowed paths
        if allowed_paths = load_allowed_paths
          allowed_paths.each do |path|
            expanded = path.starts_with?("~") ? path.sub("~", ENV.fetch("HOME", "")) : path
            restrictions.add_read_write(expanded)
          end
        end

        max_retries = 2 # Allow one retry after access granted
        attempt = 0

        while attempt < max_retries
          attempt += 1

          begin
            # Execute the tool directly in an isolated fiber with Landlock
            result = execute_tool_in_isolated_context(tool_name, arguments, restrictions)

            # Check for permission denied in result
            if result.includes?("Permission denied") || result.includes?("permission denied")
              path = extract_path_from_error(result)

              if path && attempt < max_retries
                puts "[ToolMonitor] Access denied for: #{path}"
                puts "[ToolMonitor] Requesting access..."

                access_result = LandlockSocket.request_access(path)

                case access_result
                when LandlockSocket::AccessResult::Granted
                  puts "[ToolMonitor] Access granted, retrying..."
                  restrictions.add_read_write(path)
                  next
                when LandlockSocket::AccessResult::DeniedSuggestPlayground
                  playground_path = File.join(ENV.fetch("HOME", ""), ".crybot", "playground")
                  return "Error: Access denied for #{path}. Suggested using playground (#{playground_path})."
                else
                  return "Error: Access denied for #{path}."
                end
              elsif path
                return "Error: Access denied for #{path}."
              end
            end

            return result
          rescue e : Exception
            # Check if this is a timeout from ToolRunner
            if e.message.try(&.includes?("timed out"))
              return "Error: Tool execution timed out"
            end
            return "Error: #{e.message}"
          end
        end

        "Error: Maximum retries exceeded"
      end

      # Execute tool in an isolated context with Landlock
      private def self.execute_tool_in_isolated_context(tool_name : String, arguments : Hash(String, JSON::Any), restrictions : ::ToolRunner::Landlock::Restrictions) : String
        # Create channels for result and error
        result_channel = Channel(String).new
        error_channel = Channel(Exception).new

        # Create isolated execution context
        _isolated_context = Fiber::ExecutionContext::Isolated.new("ToolExecution", spawn_context: Fiber::ExecutionContext.default) do
          begin
            # Apply Landlock restrictions first
            if restrictions.path_rules.empty? || !::ToolRunner::Landlock.available?
              # No restrictions to apply or Landlock not available - continue without sandboxing
            elsif !restrictions.apply
              error_channel.send(Exception.new("Failed to apply Landlock restrictions"))
              next
            end

            # Get the tool from registry
            tool = Tools::Registry.get(tool_name)
            if tool.nil?
              result_channel.send("Error: Tool '#{tool_name}' not found")
              next
            end

            # Execute the tool
            result = tool.execute(arguments)
            result_channel.send(result)
          rescue e : Exception
            error_channel.send(e)
          end
        end

        # Wait for result with timeout
        select
        when result = result_channel.receive
          return result
        when error = error_channel.receive
          raise error
        when timeout(30.seconds)
          raise Exception.new("Tool execution timed out")
        end
      end

      # Extract file path from permission denied error
      private def self.extract_path_from_error(error_msg : String) : String?
        match = error_msg.match(/(['"]?)(\/[^\s'\"]+)\1(?=\s*:?\s*Permission\s+denied)/i)
        match ? match[2] : nil
      end

      # Load user-configured allowed paths
      private def self.load_allowed_paths : Array(String)?
        # TODO: Load from config.yml landlock.allowed_paths
        [] of String
      end
    end
  end
end
