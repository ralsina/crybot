require "json"
require "../../session/manager"
require "../../config/loader"
require "../../agent/loop"

module Crybot
  module Web
    module Handlers
      class VoiceHandler
        def initialize(@agent : Agent::Loop, @sessions : Session::Manager)
        end

        # GET /api/voice/conversations - Get voice conversations
        def list_conversations(env) : String
          # Voice sessions use "voice_" prefix
          all_sessions = @sessions.list_sessions
          voice_sessions = all_sessions.select(&.starts_with?("voice"))

          # For now, there's typically one voice session
          # Return the most recent one or create a default
          if voice_sessions.empty?
            # Return empty list with info
            {
              conversations: [] of String,
              count:         0,
              note:          "No voice conversations yet. Use voice mode to start one.",
            }.to_json
          else
            voice_sessions.map do |session_id|
              {
                id:     session_id,
                title:  "Voice Chat",
                active: true,
              }
            end.to_json
          end
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        # GET /api/voice/conversation/current - Get current voice conversation messages
        def get_current(env) : String
          # Find the most recent voice session
          all_sessions = @sessions.list_sessions
          voice_sessions = all_sessions.select(&.starts_with?("voice"))

          if voice_sessions.empty?
            session_id = "voice_default"
            messages = [] of Providers::Message
          else
            # Prefer "voice" if it exists, otherwise use the last one
            session_id = voice_sessions.includes?("voice") ? "voice" : voice_sessions.last
            messages = @sessions.get_or_create(session_id)
          end

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

        # POST /api/voice/message - Send a message to the voice session
        def send_message(env) : String
          # Parse request body
          body = env.request.body.try(&.gets_to_end) || ""
          data = JSON.parse(body)

          content = data["content"]?.try(&.as_s) || ""

          if content.empty?
            env.response.status_code = 400
            return {error: "Message content is required"}.to_json
          end

          # Process with agent using "voice" session key
          session_key = "voice"
          agent_response = @agent.process(session_key, content)

          puts "[Voice] Received response: #{agent_response.response[0..100]}..."

          # Speak the response aloud using TTS
          speak_response(agent_response.response)

          # The response will also be sent via WebSocket broadcast by the session save callback
          {
            status: "sent",
            session: session_key,
          }.to_json
        rescue e : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        private def speak_response(text : String) : Nil
          # Simple TTS implementation for web-originated voice messages
          # This uses the same approach as VoiceListener but simplified
          return if text.empty?

          puts "[Voice] Speaking response: #{text[0..50]}..."

          # Get piper model from config
          config = Config::Loader.load
          voice_config = config.voice
          return unless voice_config

          piper_model = voice_config.piper_model
          piper_path = voice_config.piper_path || "/usr/bin/piper-tts"

          puts "[Voice] piper_model: #{piper_model}, piper_path: #{piper_path}"

          # Check if piper is available
          piper_available = piper_model &&
                            (File.info?(piper_path)) &&
                            (piper_info = File.info?(piper_path)) &&
                            piper_info.permissions.includes?(File::Permissions::OwnerExecute)

          puts "[Voice] piper_available: #{piper_available}"

          # Use piper if available, otherwise festival (or just log)
          begin
            if piper_available
              puts "[Voice] Using piper TTS"
              # Use piper TTS
              clean_text = text.gsub(/[\p{Emoji}\p{Emoji_Presentation}]/, "").strip
              command = "echo \"#{clean_text.gsub("\"", "\\\"")}\" | #{piper_path} -m #{piper_model} --output_raw --sentence_silence 0 2>/dev/null | paplay --raw --format=s16le --channels=1 --rate=22050"
              puts "[Voice] Running: #{command[0..100]}..."
              Process.run("sh", ["-c", command])
              puts "[Voice] TTS completed successfully"
            else
              # Fallback to festival or just log
              puts "[Voice] Piper not available, trying festival"
              # Try festival as fallback
              temp_file = "/tmp/voice_tts.txt"
              File.write(temp_file, text)
              Process.run("festival", ["--tts", temp_file])
              File.delete(temp_file) if File.exists?(temp_file)
              puts "[Voice] Festival TTS completed"
            end
          rescue tts_error
            puts "[Voice] TTS error: #{tts_error.message}"
          end
        end

        # POST /api/voice/push-to-talk - Activate push-to-talk
        def activate_push_to_talk(env) : String
          ptt_flag_path = Config::Loader.config_dir / "voice_ptt_active"

          # Create the flag file
          File.write(ptt_flag_path, "")

          {
            status:  "activated",
            message: "Push-to-talk activated. Speak now.",
          }.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        # DELETE /api/voice/push-to-talk - Deactivate push-to-talk
        def deactivate_push_to_talk(env) : String
          ptt_flag_path = Config::Loader.config_dir / "voice_ptt_active"

          # Remove the flag file
          File.delete(ptt_flag_path) if File.exists?(ptt_flag_path)

          {
            status:  "deactivated",
            message: "Push-to-talk deactivated.",
          }.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        # GET /api/voice/push-to-talk/status - Get push-to-talk status
        def push_to_talk_status(env) : String
          ptt_flag_path = Config::Loader.config_dir / "voice_ptt_active"
          active = File.exists?(ptt_flag_path)

          {
            active: active,
          }.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end
      end
    end
  end
end
