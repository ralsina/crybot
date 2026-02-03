require "json"
require "../../session/manager"
require "../../config/loader"

module Crybot
  module Web
    module Handlers
      class VoiceHandler
        def initialize(@sessions : Session::Manager)
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
