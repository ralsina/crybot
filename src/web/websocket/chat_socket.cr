require "http/web_socket"
require "json"
require "random/secure"
require "../../session/manager"
require "../../agent/loop"
require "../../agent/cancellation"
require "../handlers/logs_handler"

module Crybot
  module Web
    class ChatSocket
      property socket_id : String

      @@connections = Array(HTTP::WebSocket).new
      @@mutex = Mutex.new
      @@cancel_channels = Hash(String, Channel(Nil)).new
      @@cancel_mutex = Mutex.new

      def initialize(@agent : Agent::Loop, @sessions : Session::Manager)
        @socket_id = ""
        @session_id = ""
      end

      def self.broadcast(message_type : String, data : Hash(String, JSON::Any)) : Nil
        @@mutex.synchronize do
          # Build payload hash
          payload_hash = Hash(String, JSON::Any).new
          payload_hash["type"] = JSON::Any.new(message_type)

          data.each do |key, value|
            payload_hash[key] = value
          end

          payload = payload_hash.to_json

          @@connections.each do |socket|
            begin
              socket.send(payload)
            rescue e : Exception
              # Connection may be closed, ignore
            end
          end
        end
      end

      def self.connections_count : Int32
        @@mutex.synchronize { @@connections.size }
      end

      def on_open(socket) : Nil
        # Generate unique socket ID and session ID
        @socket_id = generate_session_key
        @session_id = "web_#{Random::Secure.hex(16)}"

        # Store session_id on the socket for later use
        socket.__session_id = @session_id

        # Add to connections list
        @@mutex.synchronize do
          @@connections << socket
        end

        # TODO: Fix logging
        # Crybot::Web::Handlers::LogsHandler.log("INFO", "Web client connected (session: #{@session_id})")

        # Send welcome message
        socket.send({
          type:       "connected",
          session_id: @session_id,
          socket_id:  @socket_id,
        }.to_json)
      end

      def on_message(socket, message : String) : Nil
        data = JSON.parse(message)

        case data["type"]?.try(&.as_s)
        when "message"
          handle_chat_message(socket, data)
        when "history_request"
          session_id = data["session_id"]?.try(&.as_s) || @session_id
          send_history(socket, session_id)
        when "session_switch"
          switch_session(socket, data)
        when "cancel_request"
          handle_cancel_request(socket)
        else
          socket.send({
            type:    "error",
            message: "Unknown message type",
          }.to_json)
        end
      rescue e : JSON::ParseException
        socket.send({
          type:    "error",
          message: "Invalid JSON",
        }.to_json)
      rescue e : Exception
        socket.send({
          type:    "error",
          message: e.message,
        }.to_json)
      end

      def on_close(socket) : Nil
        # Remove from connections list
        @@mutex.synchronize do
          @@connections.delete(socket)
        end
      end

      private def generate_session_key : String
        "sock_#{Random::Secure.hex(8)}"
      end

      private def handle_chat_message(socket, data : JSON::Any) : Nil
        session_id = data["session_id"]?.try(&.as_s) || @session_id
        content = data["content"]?.try(&.as_s) || ""

        if content.empty?
          socket.send({
            type:    "error",
            message: "Message content is empty",
          }.to_json)
          return
        end

        # Log incoming message
        puts "[Web] [Chat] Session: #{session_id}"
        puts "[Web] [Chat] User: #{content}"

        # Send acknowledgment that message is being processed
        socket.send({
          type:   "status",
          status: "processing",
        }.to_json)

        # Spawn agent request in a background fiber
        response_channel = Channel(Agent::AgentResponse?).new
        cancel_channel = Channel(Nil).new

        # Register cancel channel for this session
        @@cancel_mutex.synchronize do
          @@cancel_channels[session_id] = cancel_channel
        end

        spawn do
          begin
            response = @agent.process(session_id, content)
            response_channel.send(response)
          rescue e : Exception
            response_channel.send(nil)
          end
        end

        # Wait for either response or cancellation
        agent_response = nil
        cancelled = false

        select
        when r = response_channel.receive
          agent_response = r
        when cancel_channel.receive
          cancelled = true
        end

        # If cancelled, discard the response when it arrives
        if cancelled
          spawn { response_channel.receive? }
          puts "[Web] [Chat] Request cancelled"
          socket.send({
            type:    "cancelled",
            message: "Request was cancelled by user",
          }.to_json)
          return
        end

        # Log response (truncated if long)
        if agent_response
          response_preview = agent_response.response.size > 200 ? "#{agent_response.response[0..200]}..." : agent_response.response
          puts "[Web] [Chat] Assistant: #{response_preview}"

          # Log tool executions
          agent_response.tool_executions.each do |exec|
            status = exec.success? ? "✓" : "✗"
            puts "[Web] [Tool] #{status} #{exec.tool_name}"
            if exec.tool_name == "exec" || exec.tool_name == "exec_shell"
              args_str = exec.arguments.map { |k, v| "#{k}=#{v}" }.join(" ")
              puts "[Web]       Command: #{args_str}"
              result_preview = exec.result.size > 200 ? "#{exec.result[0..200]}..." : exec.result
              puts "[Web]       Output: #{result_preview}"
            end
          end

          # Send response with tool executions
          tool_executions_json = agent_response.tool_executions.map(&.to_h).map { |hash| JSON::Any.new(hash) }
          socket.send({
            type:            "response",
            session_id:      session_id,
            content:         agent_response.response,
            tool_executions: JSON::Any.new(tool_executions_json),
            timestamp:       Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"),
          }.to_json)
        else
          socket.send({
            type:    "error",
            message: "No response from agent",
          }.to_json)
        end
      end

      private def send_history(socket, session_id : String) : Nil
        messages = @sessions.get_or_create(session_id)

        socket.send({
          type:       "history",
          session_id: session_id,
          messages:   messages.map do |msg|
            {
              role:    msg.role,
              content: msg.content,
            }
          end,
        }.to_json)
      end

      private def switch_session(socket, data : JSON::Any) : Nil
        new_session_id = data["session_id"]?.try(&.as_s)

        if new_session_id.nil? || new_session_id.empty?
          # Create new session
          @session_id = "web_#{Random::Secure.hex(16)}"
        else
          @session_id = new_session_id
        end

        socket.__session_id = @session_id

        socket.send({
          type:       "session_switched",
          session_id: @session_id,
        }.to_json)
      end

      private def handle_cancel_request(socket) : Nil
        puts "[Web] [Chat] Cancel request received"

        # Cancel at the agent level
        Agent::CancellationManager.cancel_current

        # Signal the cancel channel for this session
        session_id = @session_id
        cancel_channel = @@cancel_mutex.synchronize { @@cancel_channels[session_id]? }

        if cancel_channel
          # Send twice: once for spinner, once for main fiber
          cancel_channel.send(nil)
          cancel_channel.send(nil)
        end

        socket.send({
          type: "cancel_acknowledged",
        }.to_json)
      end
    end
  end
end

# Extend HTTP::WebSocket to store custom data
module HTTP
  class WebSocket
    property __session_id : String = ""
  end
end
