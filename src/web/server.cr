require "kemal"
require "../agent/loop"
require "../session/manager"
require "../scheduled_tasks/registry"
require "../channels/unified_registry"
require "../channels/web_channel"
require "./handlers/*"
require "./websocket/*"
require "./middleware/*"
require "./assets"
require "baked_file_handler"

module Crybot
  module Web
    class Server
      getter config, agent, sessions

      def initialize(@config : Config::ConfigFile, @agent : Agent::Loop)
        @sessions = Session::Manager.instance
      end

      def start : Nil
        # Register config for scheduled tasks lazy initialization
        ScheduledTasks::Registry.instance.config = @config

        # Register WebChannel with UnifiedRegistry for scheduled task forwarding
        web_channel = Channels::WebChannel.new
        Channels::UnifiedRegistry.register(web_channel)
        puts "[#{Time.local.to_s("%H:%M:%S")}] Web channel registered for scheduled task forwarding"

        # Setup Kemal configuration
        Kemal.config.port = @config.web.port
        Kemal.config.host_binding = @config.web.host

        # Setup session save callback for broadcasting updates
        setup_session_callbacks

        # Setup middleware
        setup_middleware

        # Setup routes
        setup_routes

        # Start Kemal
        Kemal.run
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def setup_session_callbacks : Nil
        @sessions.on_save do |session_key, messages|
          last_message = messages.last?
          if last_message && last_message.role == "assistant"
            # Broadcast for telegram, voice, and web chat sessions
            if session_key.starts_with?("telegram:") || session_key == "voice" || session_key.starts_with?("web_")
              # Get the chat ID for telegram sessions
              chat_id = session_key
              message_type = "external_message"

              if session_key.starts_with?("telegram:")
                parts = session_key.split(":", 2)
                chat_id = parts.size >= 2 ? parts[1] : session_key
                message_type = "telegram_message"
              elsif session_key == "voice"
                message_type = "voice_message"
              elsif session_key.starts_with?("web_")
                # For web sessions, use the session_id as chat_id
                chat_id = session_key
                message_type = "web_message"
              end

              # Sanitize the session key to match what the web UI expects
              # The Session::Manager sanitizes keys by replacing special chars with underscore
              sanitized_key = session_key.gsub(/[^a-zA-Z0-9_-]/, "_")

              puts "[Web] Broadcasting #{message_type} for sanitized_key=#{sanitized_key}, chat_id=#{chat_id}"

              # Prepare the data for broadcast
              data = Hash(String, JSON::Any).new
              data["session_key"] = JSON::Any.new(sanitized_key)
              data["chat_id"] = JSON::Any.new(chat_id)
              data["source"] = JSON::Any.new(message_type == "telegram_message" ? "telegram" : message_type == "voice_message" ? "voice" : "web")
              data["role"] = JSON::Any.new(last_message.role)
              data["content"] = JSON::Any.new(last_message.content || "")
              data["timestamp"] = JSON::Any.new(Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"))

              # Broadcast to all connected clients
              Crybot::Web::ChatSocket.broadcast(message_type, data)
            end
          end
        end
      end

      private def setup_middleware : Nil
        # Add CORS headers if enabled
        if @config.web.enable_cors?
          use Crybot::Web::CORSHandler.new(@config.web.allowed_origins)
        end

        # Add baked file handler for static assets (embedded in binary)
        use BakedFileHandler::BakedFileHandler.new(Crybot::Web::BakedAssets)

        # Add authentication middleware (but allow public paths)
        use Crybot::Web::Middleware::AuthMiddleware.new(@config)
      end

      private def setup_routes : Nil
        # WebSocket endpoint
        ws "/ws/chat" do |socket|
          handle_chat_websocket(socket)
        end

        # API: Health check
        get "/api/health" do |env|
          Handlers::APIHandler.health(env)
        end

        # API: Status
        get "/api/status" do |env|
          Handlers::APIHandler.status(env, @config, @agent, @sessions)
        end

        # API: Auth validation
        post "/api/auth/validate" do |env|
          Handlers::AuthHandler.validate(env, @config)
        end

        # API: Chat (REST endpoint as alternative to WebSocket)
        post "/api/chat" do |env|
          handler = Handlers::ChatHandler.new(@agent, @sessions)
          handler.handle_message(env)
        end

        # API: Sessions
        get "/api/sessions" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.list_sessions(env)
        end

        get "/api/sessions/:id" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.get_session(env)
        end

        delete "/api/sessions/:id" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.delete_session(env)
        end

        patch "/api/sessions/:id/metadata" do |env|
          handler = Handlers::SessionHandler.new(@sessions)
          handler.update_metadata(env)
        end

        # API: Config
        get "/api/config" do |env|
          handler = Handlers::ConfigHandler.new(@config)
          handler.get_config(env)
        end

        put "/api/config" do |env|
          handler = Handlers::ConfigHandler.new(@config)
          handler.update_config(env)
        end

        # API: Telegram conversations
        get "/api/telegram/conversations" do |env|
          handler = Handlers::TelegramHandler.new(@sessions)
          handler.list_conversations(env)
        end

        get "/api/telegram/conversations/:id" do |env|
          handler = Handlers::TelegramHandler.new(@sessions)
          handler.get_conversation(env)
        end

        post "/api/telegram/conversations/:id/message" do |env|
          handler = Handlers::TelegramHandler.new(@sessions)
          handler.send_message(env)
        end

        # API: Voice conversations
        get "/api/voice/conversations" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.list_conversations(env)
        end

        get "/api/voice/conversation/current" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.get_current(env)
        end

        post "/api/voice/message" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.send_message(env)
        end

        # API: Voice push-to-talk
        post "/api/voice/push-to-talk" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.activate_push_to_talk(env)
        end

        delete "/api/voice/push-to-talk" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.deactivate_push_to_talk(env)
        end

        get "/api/voice/push-to-talk/status" do |env|
          handler = Handlers::VoiceHandler.new(@agent, @sessions)
          handler.push_to_talk_status(env)
        end

        # API: Logs
        get "/api/logs" do |env|
          handler = Handlers::LogsHandler.new
          handler.get_logs(env)
        end

        # API: Skills
        get "/api/skills" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.list_skills(env)
        end

        get "/api/skills/:skill" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.get_skill(env)
        end

        put "/api/skills/:skill" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.save_skill(env)
        end

        post "/api/skills" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.save_skill(env)
        end

        delete "/api/skills/:skill" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.delete_skill(env)
        end

        post "/api/skills/reload" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.reload_skills(env)
        end

        post "/api/skills/credentials" do |env|
          handler = Handlers::SkillsHandler.new(@agent.skill_manager)
          handler.set_credentials(env)
        end

        # API: Reload skills in the running agent
        post "/api/agent/reload-skills" do |_|
          results = @agent.reload_skills

          loaded_count = results.count { |result| result[:status] == "loaded" }
          missing_count = results.count { |result| result[:status] == "missing_credentials" }
          error_count = results.count { |result| result[:status] == "error" }

          {
            success: true,
            message: "Skills reloaded in running agent",
            loaded:  loaded_count,
            missing: missing_count,
            errors:  error_count,
            results: results.map do |result|
              {
                name:   result[:name],
                status: result[:status],
                error:  result[:error],
              }
            end,
          }.to_json
        end

        # API: Reload MCP servers
        post "/api/agent/reload-mcp" do |_|
          results = @agent.reload_mcp

          connected_count = results.count { |result| result[:status] == "connected" }
          error_count = results.count { |result| result[:status] == "error" }

          {
            success:   true,
            message:   "MCP servers reloaded",
            connected: connected_count,
            errors:    error_count,
            results:   results.map do |result|
              {
                name:   result[:name],
                status: result[:status],
                error:  result[:error],
              }
            end,
          }.to_json
        end

        # API: Scheduled Tasks
        get "/api/scheduled-tasks" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.list_tasks(env)
        end

        post "/api/scheduled-tasks" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.create_task(env)
        end

        put "/api/scheduled-tasks/:id" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.update_task(env)
        end

        delete "/api/scheduled-tasks/:id" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.delete_task(env)
        end

        post "/api/scheduled-tasks/:id/run" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.run_task(env)
        end

        post "/api/scheduled-tasks/reload" do |env|
          handler = Handlers::ScheduledTasksHandler.new
          handler.reload_tasks(env)
        end
      end

      private def handle_chat_websocket(socket) : Nil
        chat_socket = ChatSocket.new(@agent, @sessions)

        # This runs when the WebSocket connection opens
        chat_socket.on_open(socket)

        socket.on_message do |message|
          chat_socket.on_message(socket, message)
        end

        socket.on_close do
          chat_socket.on_close(socket)
        end
      end
    end
  end
end
