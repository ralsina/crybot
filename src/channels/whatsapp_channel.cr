require "http/web_socket"
require "json"
require "./channel"
require "../agent/loop"
require "../session/manager"

module Crybot
  module Channels
    # WhatsApp channel - handles WhatsApp bot interactions via Baileys bridge
    # Connects to a Node.js bridge that uses @whiskeysockets/baileys for WhatsApp Web protocol
    class WhatsAppChannel < Channel
      Log = ::Log.for("whatsapp")

      @agent : Agent::Loop
      @sessions : Session::Manager
      @bridge_url : String
      @allowed_users : Array(String)
      @ws : HTTP::WebSocket?
      @connected : Bool = false
      @running : Bool = false
      @reconnect_delay : Time::Span = 5.seconds

      getter agent

      def initialize(config : Config::ChannelsConfig::WhatsAppConfig, @agent : Agent::Loop)
        @sessions = Session::Manager.instance
        @bridge_url = config.bridge_url || "ws://localhost:3001"
        @allowed_users = config.allow_from

        puts "[WhatsApp] WhatsApp channel initialized (bridge: #{@bridge_url})"
      end

      def name : String
        "whatsapp"
      end

      def start : Nil
        @running = true
        Log.info { "Starting WhatsApp channel, connecting to bridge at #{@bridge_url}" }

        spawn do
          while @running
            begin
              connect_to_bridge
            rescue ex : Exception
              @connected = false
              Log.warn { "Bridge connection error: #{ex.message}" }
            end

            if @running
              Log.info { "Reconnecting to bridge in #{@reconnect_delay.to_i} seconds..." }
              sleep @reconnect_delay
            end
          end
        end
      end

      def stop : Nil
        @running = false
        @ws.try(&.close)
        @connected = false
        Log.info { "WhatsApp channel stopped" }
      end

      def send_message(message : ChannelMessage) : Nil
        ws = @ws
        return unless ws
        return unless @connected

        # Send message to WhatsApp via bridge
        data = {
          type:    "send",
          jid:     message.chat_id,
          content: message.content,
        }

        begin
          ws.send(data.to_json)
          Log.debug { "Sent message to #{message.chat_id}" }
        rescue ex : Exception
          Log.error { "Failed to send message: #{ex.message}" }
        end
      end

      def session_key(chat_id : String) : String
        # WhatsApp sessions use the pattern "whatsapp:PHONE_NUMBER"
        # Extract phone number from JID (remove @s.whatsapp.net suffix)
        phone_number = chat_id.split('@').first
        "#{name}:#{phone_number}"
      end

      def webhook_based? : Bool
        false # Direct WebSocket connection, not webhook-based
      end

      def healthy? : Bool
        @connected
      end

      def supports_markdown? : Bool
        false # WhatsApp has its own formatting
      end

      private def connect_to_bridge : Nil
        uri = URI.parse(@bridge_url)
        host = uri.host || "localhost"
        port = uri.port || 3001
        path = uri.path
        path = "/" if path.empty?

        Log.info { "Connecting to bridge at #{host}:#{port}#{path}" }

        ws = HTTP::WebSocket.new(host: host, path: path, port: port)

        ws.on_message do |raw|
          handle_bridge_message(raw)
        end

        ws.on_close do
          @connected = false
          Log.info { "Bridge disconnected" }
        end

        ws.on_error do |error|
          Log.error { "WebSocket error: #{error}" }
        end

        @ws = ws
        Log.info { "Connected to WhatsApp bridge" }
        @connected = true

        ws.run
      end

      private def handle_bridge_message(raw : String) : Nil
        data = JSON.parse(raw)
        msg_type = data["type"]?.try(&.as_s)

        case msg_type
        when "message"
          handle_incoming_message(data)
        when "status"
          handle_status_update(data)
        when "qr"
          handle_qr_code(data)
        when "error"
          handle_error(data)
        when "pong"
          # Keepalive response, ignore
        else
          Log.debug { "Unknown message type: #{msg_type}" }
        end
      rescue ex : JSON::ParseException
        Log.error { "Failed to parse bridge message: #{ex.message}" }
      rescue ex : Exception
        Log.error { "Error handling bridge message: #{ex.message}" }
      end

      private def handle_incoming_message(data : JSON::Any) : Nil
        jid = data["pn"]?.try(&.as_s) || ""
        content = data["content"]?.try(&.as_s) || ""

        # Extract phone number from JID
        phone_number = jid.split('@').first

        # Check if sender is allowed
        return unless allowed?(phone_number)

        # Create metadata
        metadata = Hash(String, String).new
        metadata["message_id"] = data["id"]?.try(&.as_s) || ""
        metadata["timestamp"] = data["timestamp"]?.try(&.as_s) || ""
        metadata["is_group"] = data["isGroup"]?.try(&.as_s) || "false"
        metadata["push_name"] = data["pushName"]?.try(&.as_s) || ""

        is_group = data["isGroup"]?.try(&.as_bool) || false

        Log.info {
          msg_preview = content[0...50]
          msg_preview += "..." if content.size > 50
          "Received #{is_group ? "group" : "direct"} message from #{phone_number}: #{msg_preview}"
        }

        # Create channel message
        msg = ChannelMessage.new(
          channel: "whatsapp",
          sender_id: phone_number,
          chat_id: jid,
          content: content,
          metadata: metadata
        )

        # Process the message through the channel
        handle_message(msg)
      end

      private def handle_status_update(data : JSON::Any) : Nil
        status = data["status"]?.try(&.as_s)

        case status
        when "connected"
          @connected = true
          Log.info { "WhatsApp bridge status: connected" }
        when "disconnected"
          @connected = false
          Log.warn { "WhatsApp bridge status: disconnected" }
        when "logged_out"
          @connected = false
          Log.error { "WhatsApp logged out - please rescan QR code in bridge" }
        else
          Log.debug { "WhatsApp status: #{status}" }
        end
      end

      private def handle_qr_code(data : JSON::Any) : Nil
        Log.info { "QR code available - scan with WhatsApp mobile app" }
        Log.info { "Open WhatsApp > Settings > Linked Devices > Link a Device" }
        # The QR code is displayed in the bridge terminal
      end

      private def handle_error(data : JSON::Any) : Nil
        error_msg = data["error"]?.try(&.as_s) || "Unknown error"
        Log.error { "Bridge error: #{error_msg}" }
      end

      # Check if a phone number is allowed to use the bot
      # Empty allow_from = deny all (secure default)
      # ["*"] = allow all
      # Otherwise check if phone number is in allowlist
      private def allowed?(phone_number : String) : Bool
        # Deny by default if no allowlist configured
        return false if @allowed_users.empty?
        # Allow all if wildcard is set
        return true if @allowed_users.includes?("*")
        # Check if phone number is in allowlist
        @allowed_users.includes?(phone_number)
      end

      # Send ping to keep connection alive
      def ping : Nil
        ws = @ws
        return unless ws && @connected

        begin
          ws.send({type: "ping"}.to_json)
        rescue ex : Exception
          Log.debug { "Failed to send ping: #{ex.message}" }
        end
      end
    end
  end
end
