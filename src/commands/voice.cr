require "../config/loader"
require "../agent/loop"
require "../agent/voice_listener"

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
          puts "Error: API key not configured for provider '#{provider}'."
          puts "Please edit #{Config::Loader.config_file} and add your API key"
          return
        end

        # Check for whisper.cpp
        whisper_path = ENV["WHISPER_PATH"]? || find_whisper_binary
        unless whisper_path && File.info?(whisper_path) && File.info(whisper_path).permissions.includes?(File::Permissions::OwnerExecute)
          puts "Error: whisper.cpp not found."
          puts
          puts "Please install whisper.cpp:"
          puts "  git clone https://github.com/ggerganov/whisper.cpp"
          puts "  cd whisper.cpp"
          puts "  make"
          puts
          puts "Then set WHISPER_PATH environment variable:"
          puts "  export WHISPER_PATH=/path/to/whisper.cpp/whisper"
          puts
          puts "Or add to ~/.crybot/config.yml:"
          puts "  voice:"
          puts "    whisper_path: /path/to/whisper"
          return
        end

        # Create agent loop
        agent_loop = Crybot::Agent::Loop.new(config)

        # Create and start voice listener
        listener = Crybot::Agent::VoiceListener.new(agent_loop)

        # Handle Ctrl+C gracefully
        Signal::INT.trap do
          listener.stop
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

      private def self.find_whisper_binary : String?
        paths = [
          File.expand_path("~/.local/bin/whisper"),
          "/usr/local/bin/whisper",
          "/usr/bin/whisper",
          File.expand_path("../whisper.cpp/whisper", Dir.current),
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
