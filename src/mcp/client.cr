require "json"
require "http"
require "channel"

module Crybot
  module MCP
    # MCP JSON-RPC 2.0 Client
    # Implements the Model Context Protocol for connecting to external tools/resources
    class Client
      @request_id : Int64 = 0_i64
      @server_name : String
      @command : String?
      @url : String?
      @process : Process?
      @running : Bool = false
      @response_buffer = ""
      @response_mutex = Mutex.new
      @response_channel = Channel(String?).new(1)
      @reader_fiber : Fiber?

      def initialize(@server_name : String, @command : String? = nil, @url : String? = nil)
        raise "Either command or url must be provided" if @command.nil? && @url.nil?
      end

      def start : Nil
        if @command
          start_stdio_server
        else
          raise "HTTP MCP servers not yet supported"
        end
        @running = true

        start_reader_fiber

        initialize_mcp
      end

      def stop : Nil
        @running = false
        if @reader_fiber
          # Give the fiber a moment to finish naturally
          sleep 0.1.seconds
        end
        if process = @process
          process.terminate
          @process = nil
        end
      end

      def list_tools : Array(Tool)
        send_request("tools/list") do |response|
          tools = response.dig?("result", "tools")
          if tools && tools.as_a?
            tools.as_a.map { |tool_json| Tool.from_json(tool_json.to_json) }
          else
            [] of Tool
          end
        end
      end

      def call_tool(name : String, arguments : Hash(String, JSON::Any)) : ToolCallResult
        send_request("tools/call", {
          "name"      => name,
          "arguments" => arguments,
        }) do |response|
          ToolCallResult.from_json(response.dig?("result").to_json)
        end
      end

      def list_resources : Array(Resource)
        send_request("resources/list") do |response|
          resources = response.dig?("result", "resources")
          if resources && resources.as_a?
            resources.as_a.map { |resource_json| Resource.from_json(resource_json.to_json) }
          else
            [] of Resource
          end
        end
      end

      def read_resource(uri : String) : ResourceContents
        send_request("resources/read", {
          "uri" => uri,
        }) do |response|
          ResourceContents.from_json(response.dig?("result").to_json)
        end
      end

      private def start_stdio_server : Nil
        command = @command
        return unless command

        parts = command.split(' ')

        @process = Process.new(parts[0], parts[1..],
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Pipe,
          clear_env: false,
        )

        # Give the server a moment to start
        sleep 0.5.seconds

        # Check if process is still alive
        current_process = @process
        if current_process && current_process.exists?
          # Process is running
        else
          raise "MCP server process failed to start"
        end
      end

      private def start_reader_fiber : Nil
        @reader_fiber = spawn do
          buffer = Bytes.new(4096)
          process = @process

          while @running && process
            begin
              bytes_read = process.output.read(buffer)
              if bytes_read && bytes_read > 0
                data = String.new(buffer[0, bytes_read])
                @response_mutex.synchronize do
                  @response_buffer += data
                end
                @response_channel.send(data) rescue nil
              elsif bytes_read == 0
                # EOF
                break
              end
            rescue e : Exception
              break
            end
          end
          @response_channel.send(nil)
        end
      end

      private def initialize_mcp : Nil
        send_request("initialize", {
          "protocolVersion" => "2024-11-05",
          "capabilities"    => {
            "tools"     => true,
            "resources" => true,
          },
          "clientInfo" => {
            "name"    => "crybot",
            "version" => "0.1.0",
          },
        }) do |_|
          send_notification("initialized")
        end
      end

      private def send_request(method : String, params = nil, & : JSON::Any -> _)
        @request_id += 1
        request = build_request(@request_id, method, params)

        response = send_and_receive(request)

        if error = response["error"]?
          raise "MCP Error (#{method}): #{error}"
        end

        yield response
      end

      private def send_notification(method : String, params = nil) : Nil
        request = {
          "jsonrpc" => "2.0",
          "method"  => method,
          "params"  => params,
        }.to_json

        send_to_server(request)
      end

      private def build_request(id : Int64, method : String, params) : String
        {
          "jsonrpc" => "2.0",
          "id"      => id,
          "method"  => method,
          "params"  => params,
        }.to_json
      end

      private def send_and_receive(request : String) : JSON::Any
        send_to_server(request)
        receive_from_server
      end

      private def send_to_server(data : String) : Nil
        if process = @process
          message = data + "\n"
          process.input << message
          process.input.flush
        else
          raise "MCP server process not running"
        end
      end

      private def receive_from_server : JSON::Any
        timeout = 5.seconds
        start_time = Time.instant

        # Wait for data with timeout
        while Time.instant - start_time < timeout
          buffer_content = @response_mutex.synchronize { @response_buffer }

          if !buffer_content.strip.empty?
            # Try to parse each line separately (MCP responses are newline-terminated)
            lines = buffer_content.split('\n', remove_empty: true)

            lines.each do |line|
              next if line.strip.empty?

              begin
                response = JSON.parse(line)
                # Remove this line from the buffer
                line_with_newline = line + "\n"
                new_content = buffer_content.sub(line_with_newline, "")
                @response_mutex.synchronize do
                  @response_buffer = new_content
                end
                return response
              rescue e : JSON::ParseException
                # This line isn't complete JSON yet, try next line
              end
            end
          end

          sleep 0.01.seconds
        end

        # Timeout - no valid response received
        buffer_content = @response_mutex.synchronize { @response_buffer }
        if buffer_content.strip.empty?
          raise "MCP server not responding (timeout)"
        end

        # Try parsing the whole buffer as one JSON
        begin
          response = JSON.parse(buffer_content)
          @response_mutex.synchronize do
            @response_buffer = ""
          end
          response
        rescue e : JSON::ParseException
          raise "MCP server response invalid JSON: #{e.message}"
        end
      end

      private def read_line_with_timeout(process : Process, timeout : Time::Span, start_time : Time::Instant) : String?
        buffer = IO::Memory.new

        while Time.instant - start_time < timeout
          char = process.output.read_char
          if char
            if char == '\n'
              return buffer.to_s
            elsif char != '\r'
              buffer << char
            end
          else
            sleep 0.01.seconds
          end
        end

        # Return whatever we have (might be empty)
        buffer.to_s if buffer.size > 0
      end

      # MCP Schema Types

      struct Tool
        include JSON::Serializable

        property name : String
        property description : String?
        property input_schema : Hash(String, JSON::Any)

        def to_crybot_tool : Tools::Base::ToolSchema
          Tools::Base::ToolSchema.new(
            name: name,
            description: description || "",
            parameters: input_schema
          )
        end
      end

      struct ToolCallResult
        include JSON::Serializable

        property content : Array(ContentItem)
        property is_error : Bool?

        def to_response_string : String
          content.map(&.to_s).join("\n")
        end
      end

      struct ContentItem
        include JSON::Serializable

        property type : String
        property text : String?
        property data : String?
        property mime_type : String?

        def to_s : String
          case type
          when "text" then text || ""
          when "resource"
            "[Resource: #{data || "unknown"}]"
          else
            "[#{type}]"
          end
        end
      end

      struct Resource
        include JSON::Serializable

        property uri : String
        property name : String
        property description : String?
        property mime_type : String?
      end

      struct ResourceContents
        include JSON::Serializable

        property contents : Array(ResourceContent)

        def to_response_string : String
          contents.map(&.to_s).join("\n")
        end
      end

      struct ResourceContent
        include JSON::Serializable

        property uri : String
        property mime_type : String?
        property text : String?

        def to_s : String
          text || "[Binary content: #{mime_type || "unknown"}]"
        end
      end
    end
  end
end
