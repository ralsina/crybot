require "../config/loader"
require "../config/watcher"
require "../channels/manager"

module Crybot
  module Commands
    class Gateway
      @watcher : Config::Watcher?

      def self.execute : Nil
        new.run
      end

      def run : Nil
        # Load config
        config = Config::Loader.load

        # Validate configuration
        return unless validate_config(config)

        # Start config watcher before starting channels
        watcher = Config::Watcher.new(Config::Loader.config_file, ->{ restart })
        @watcher = watcher
        watcher.start

        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting gateway..."
        puts "[#{Time.local.to_s("%H:%M:%S")}] Watching for config changes (restarts automatically)..."

        # Create and start channel manager
        manager = Channels::Manager.new(config)
        manager.start
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check if any channels are enabled
        unless config.channels.telegram.enabled
          puts "Error: No channels enabled."
          puts "Enable channels in #{Config::Loader.config_file}"
          puts "\nExample for Telegram:"
          puts "  channels:"
          puts "    telegram:"
          puts "      enabled: true"
          puts "      token: \"YOUR_BOT_TOKEN\""
          puts "      allow_from: [\"123456789\"]  # Optional: restrict to specific users"
          return false
        end

        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider(model)

        case provider
        when "openai"
          if config.providers.openai.api_key.empty?
            puts "Error: OpenAI API key not configured."
            puts "Please edit #{Config::Loader.config_file} and add your API key"
            return false
          end
        when "anthropic"
          if config.providers.anthropic.api_key.empty?
            puts "Error: Anthropic API key not configured."
            puts "Please edit #{Config::Loader.config_file} and add your API key"
            return false
          end
        when "openrouter"
          if config.providers.openrouter.api_key.empty?
            puts "Error: OpenRouter API key not configured."
            puts "Please edit #{Config::Loader.config_file} and add your API key"
            return false
          end
        when "vllm"
          if config.providers.vllm.api_base.empty?
            puts "Error: vLLM api_base not configured."
            puts "Please edit #{Config::Loader.config_file} and add api_base"
            return false
          end
        else # zhipu (default)
          if config.providers.zhipu.api_key.empty?
            puts "Error: z.ai API key not configured."
            puts "Please edit #{Config::Loader.config_file} and add your API key"
            return false
          end
        end

        # Check Telegram token
        if config.channels.telegram.enabled && config.channels.telegram.token.empty?
          puts "Error: Telegram enabled but token not configured."
          puts "Please edit #{Config::Loader.config_file} and add your bot token"
          puts "\nGet a bot token from @BotFather on Telegram"
          return false
        end

        true
      end

      private def detect_provider(model : String) : String
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

      private def restart : Nil
        puts "[#{Time.local.to_s("%H:%M:%S")}] Config file changed, restarting gateway..."

        # Stop the watcher
        if watcher = @watcher
          watcher.stop
        end

        # Re-exec the current process with the same arguments
        # This replaces the current process with a new one
        Process.exec(PROGRAM_NAME, ARGV)
      end
    end
  end
end
