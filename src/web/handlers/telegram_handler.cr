require "json"
require "../../session/manager"
require "../../providers/base"
require "../../channels/telegram"
require "../../channels/registry"

module Crybot
  module Web
    module Handlers
      class TelegramHandler
        def initialize(@sessions : Session::Manager)
        end

        # GET /api/telegram/conversations - List all telegram conversations
        def list_conversations(env) : String
          all_sessions = @sessions.list_sessions

          # Filter for telegram sessions (prefix "telegram_")
          telegram_sessions = all_sessions.select(&.starts_with?("telegram_"))

          conversations = telegram_sessions.map do |session_id|
            messages = @sessions.get_or_create(session_id)
            last_message = messages.last?

            {
              id:      session_id,
              title:   extract_title(session_id),
              preview: last_message.try { |msg| msg.content.try(&.[0...50]) } || "No messages",
              time:    last_message ? format_time(last_message) : "",
            }
          end

          # Sort by time (most recent first) - using session ID as proxy for now
          conversations = conversations.reverse

          {
            conversations: conversations,
            count:         conversations.size,
          }.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        # GET /api/telegram/conversations/:id - Get conversation messages
        def get_conversation(env) : String
          session_id = env.params.url["id"]

          # Ensure it's a telegram session
          unless session_id.starts_with?("telegram_")
            env.response.status_code = 400
            return {error: "Not a telegram conversation"}.to_json
          end

          messages = @sessions.get_or_create(session_id)

          {
            session_id: session_id,
            messages:   messages.map do |msg|
              {
                role:    msg.role,
                content: msg.content,
              }
            end,
          }.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        # POST /api/telegram/conversations/:id/message - Send message to telegram conversation
        # ameba:disable Metrics/CyclomaticComplexity
        def send_message(env) : String
          session_id = env.params.url["id"]
          body = env.request.body.try(&.gets_to_end) || ""
          data = JSON.parse(body)

          content = data["content"]?.try(&.as_s) || ""

          if content.empty?
            env.response.status_code = 400
            return {error: "Message content is required"}.to_json
          end

          # Get the Telegram channel from registry
          puts "[Web] Looking up Telegram channel in registry..."
          telegram_channel = Channels::Registry.telegram
          if telegram_channel.nil?
            puts "[Web] ERROR: Telegram channel not available in registry!"
            puts "[Web] Make sure the gateway feature is running"
            env.response.status_code = 503
            return {error: "Telegram channel not available. Make sure the gateway feature is started."}.to_json
          end

          puts "[Web] Found Telegram channel, processing message..."

          # Extract chat_id from session_id (format: telegram_<chat_id>)
          # Need to reconstruct the actual Telegram chat ID from session_id
          # The session manager sanitizes colons to underscores
          if session_id =~ /^telegram_(.+)$/
            chat_id = $1

            puts "[Web] Session ID: #{session_id}, extracted chat_id: #{chat_id}"

            session_key = "telegram:#{chat_id}"

            # First, send the user's message to Telegram with "FWD from web:" prefix
            # This shows in Telegram what was forwarded
            fwd_message = "📱 FWD from web:\n\n#{content}"
            puts "[Web] Sending forwarded message to Telegram..."
            telegram_channel.send_to_chat(chat_id, fwd_message)

            # Then, send the original message to the agent (without the prefix)
            # The agent's response will be sent to Telegram and web automatically
            agent = telegram_channel.agent
            puts "[Web] Processing through agent with session_key: #{session_key}"
            agent_response = agent.process(session_key, content)

            # The agent response has been broadcast to web and Telegram
            # Just return success to the web UI
            {
              status:   "sent",
              chat_id:  chat_id,
              response: agent_response.response,
            }.to_json

            {
              status:   "sent",
              chat_id:  chat_id,
              message:  "Message sent to Telegram",
            }.to_json
          else
            env.response.status_code = 400
            {error: "Invalid telegram session ID"}.to_json
          end
        rescue e : Exception
          puts "[Web] ERROR in send_message: #{e.message}"
          puts e.backtrace.join("\n") if ENV["DEBUG"]?
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        private def extract_title(session_id : String) : String
          # Extract user ID from session_id (format: telegram_<user_id>)
          if session_id =~ /^telegram_(.+)$/
            user_id = $1
            # Try to make it more readable
            if user_id.includes?("_")
              parts = user_id.split("_")
              if parts.size >= 2
                # Format: telegram_<username>_<chat_id> or similar
                username = parts[0]
                return username == "unknown" ? "Telegram Chat" : username.capitalize
              end
            end
            return "Telegram #{user_id[0...8]}"
          end
          "Unknown Chat"
        end

        private def format_time(message : Providers::Message) : String
          # For now, just return a placeholder
          # In a real implementation, messages would have timestamps
          "Recently"
        end
      end
    end
  end
end
