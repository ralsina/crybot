require "json"
require "process"
require "./tools/registry"
require "./tool_runner_impl"
require "../landlock_socket"

module Crybot
  module Agent
    # Tool Monitor - Manages tool execution in Landlocked subprocesses
    #
    # The monitor runs in the same process as the agent (no Landlock).
    # When the agent needs to execute a tool, it sends a request to the monitor.
    # The monitor spawns a landlocked subprocess, handles access denials,
    # and returns the result.
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
              result = execute_in_subprocess(request.tool_name, request.arguments)
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

      # Execute tool in a landlocked subprocess
      private def self.execute_in_subprocess(tool_name : String, arguments : Hash(String, JSON::Any)) : String
        args_json = arguments.to_json

        max_retries = 2 # Allow one retry after access granted
        attempt = 0

        while attempt < max_retries
          attempt += 1

          # Run tool runner using crybot binary
          output = IO::Memory.new
          error = IO::Memory.new

          status = Process.run(
            PROGRAM_NAME,
            ["tool-runner", tool_name, args_json],
            output: output,
            error: error
          )

          output_str = output.to_s.strip
          error_str = error.to_s.strip

          case status.exit_code
          when 0
            # Success - return output (might have debug messages mixed in)
            # Filter out [ToolRunner] debug messages
            lines = output_str.lines.reject(&.starts_with?("[ToolRunner]"))
            return lines.join("\n")
          when 42
            # Access denied - check error for path
            if error_str.starts_with?("LANDLOCK_DENIED:")
              path = error_str.sub("LANDLOCK_DENIED:", "").strip

              if attempt < max_retries
                puts "[ToolMonitor] Access denied for: #{path}"
                puts "[ToolMonitor] Requesting access through landlock monitor..."

                # Request access through the landlock monitor (rofi/terminal)
                result = LandlockSocket.request_access(path)

                case result
                when LandlockSocket::AccessResult::Granted
                  puts "[ToolMonitor] Access granted, retrying..."
                  next # Retry with new Landlock rules
                when LandlockSocket::AccessResult::DeniedSuggestPlayground
                  playground_path = File.join(ENV.fetch("HOME", ""), ".crybot", "playground")
                  return "Error: Access denied for #{path}. The user denied access and suggested using paths within the playground (#{playground_path})."
                else
                  return "Error: Access denied for #{path}. Please try again or modify allowed paths."
                end
              else
                return "Error: Access denied for #{path} and retry limit reached."
              end
            else
              # Generic access denied
              return "Error: #{error_str}"
            end
          else
            # Other error - check stderr first, then stdout
            error_msg = error_str.empty? ? output_str : error_str
            return "Error: #{error_msg}"
          end
        end

        "Error: Maximum retries exceeded"
      end
    end
  end
end
