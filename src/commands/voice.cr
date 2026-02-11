require "log"
require "../config/loader"
require "../agent/loop"
require "../agent/voice_listener"
require "../web/handlers/logs_handler"

module Crybot
  module Commands
    class Voice
      def self.execute : Nil
        # Load config
        config = Config::Loader.load

        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider_from_model(model)

        api_key_valid = case provider
                        when "openai"
                          !config.providers.openai.api_key.empty?
                        when "anthropic"
                          !config.providers.anthropic.api_key.empty?
                        when "openrouter"
                          !config.providers.openrouter.api_key.empty?
                        when "vllm"
                          !config.providers.vllm.api_base.empty?
                        else # zhipu (default)
                          !config.providers.zhipu.api_key.empty?
                        end

        unless api_key_valid
          Log.error { "Error: API key not configured for provider '#{provider}'." }
          Log.error { "Please edit #{Config::Loader.config_file} and add your API key" }
          return
        end

        # Check for whisper-stream
        whisper_stream_path = find_whisper_stream
        unless whisper_stream_path
          Log.error { "Error: whisper-stream not found." }
          Log.error { "" }
          Log.error { "Please install whisper.cpp with whisper-stream:" }
          Log.error { "  On Arch: pacman -S whisper.cpp-crypt" }
          Log.error { "  Or build from source:" }
          Log.error { "    git clone https://github.com/ggerganov/whisper.cpp" }
          Log.error { "    cd whisper.cpp" }
          Log.error { "    make whisper-stream" }
          Log.error { "" }
          Log.error { "Or add to ~/.crybot/config.yml:" }
          Log.error { "  voice:" }
          Log.error { "    whisper_stream_path: /path/to/whisper-stream" }
          return
        end

        # Create agent loop
        agent_loop = Crybot::Agent::Loop.new(config)

        # Create and start voice listener
        listener = Crybot::Agent::VoiceListener.new(agent_loop)

        # TODO: Fix logging
        # Crybot::Web::Handlers::LogsHandler.log("INFO", "Voice activated")

        # Handle Ctrl+C gracefully
        Signal::INT.trap do
          listener.stop
          # Crybot::Web::Handlers::LogsHandler.log("INFO", "Voice deactivated")
          exit
        end

        listener.start
      end

      def self.detect_provider_from_model(model : String) : String
        parts = model.split('/', 2)
        provider = parts.size == 2 ? parts[0] : nil

        provider || case model
        when /^gpt-/      then "openai"
        when /^claude-/   then "anthropic"
        when /^glm-/      then "zhipu"
        when /^deepseek-/ then "openrouter"
        when /^qwen-/     then "openrouter"
        else                   "zhipu"
        end
      end

      private def self.find_whisper_stream : String?
        paths = [
          "/usr/bin/whisper-stream",
          "/usr/local/bin/whisper-stream",
          File.expand_path("~/.local/bin/whisper-stream"),
          File.expand_path("../whisper.cpp/whisper-stream", Dir.current),
        ]

        paths.each do |path|
          if File.info?(path) && File.info(path).permissions.includes?(File::Permissions::OwnerExecute)
            return path
          end
        end

        nil
      end
    end
  end
end
