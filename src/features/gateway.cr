require "log"
require "../config/loader"
require "../channels/manager"
require "./base"

module Crybot
  module Features
    class GatewayFeature < FeatureModule
      @config : Config::ConfigFile
      @agent : Agent::Loop?
      @manager : Channels::Manager?
      @polling_fiber : Fiber?

      def initialize(@config : Config::ConfigFile)
      end

      def start : Nil
        unless validate_config(@config)
          Log.warn { "[Gateway] Config validation failed, not starting" }
          return
        end

        Log.info { "[Gateway] Starting gateway feature..." }

        # Create agent loop
        @agent = Agent::Loop.new(@config)

        # Create and start channel manager in a fiber
        @manager = Channels::Manager.new(@config)

        # Start polling in a fiber so we don't block
        @polling_fiber = spawn do
          @manager.try(&.start)
        end

        @running = true
      end

      def stop : Nil
        @running = false
        if manager = @manager
          manager.stop
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check if any channels are enabled
        unless config.channels.telegram.enabled?
          Log.warn { "[Gateway] Gateway enabled but no channels configured." }
          return false
        end

        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider(model)

        case provider
        when "openai"
          if config.providers.openai.api_key.empty?
            Log.error { "[Gateway] OpenAI API key not configured." }
            Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add your API key" }
            return false
          end
        when "anthropic"
          if config.providers.anthropic.api_key.empty?
            Log.error { "[Gateway] Anthropic API key not configured." }
            Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add your API key" }
            return false
          end
        when "openrouter"
          if config.providers.openrouter.api_key.empty?
            Log.error { "[Gateway] OpenRouter API key not configured." }
            Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add your API key" }
            return false
          end
        when "vllm"
          if config.providers.vllm.api_base.empty?
            Log.error { "[Gateway] vLLM api_base not configured." }
            Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add api_base" }
            return false
          end
        else # zhipu (default)
          if config.providers.zhipu.api_key.empty?
            Log.error { "[Gateway] z.ai API key not configured." }
            Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add your API key" }
            return false
          end
        end

        # Check Telegram token
        if config.channels.telegram.enabled? && config.channels.telegram.token.empty?
          Log.error { "[Gateway] Telegram enabled but token not configured." }
          Log.error { "[Gateway] Please edit #{Config::Loader.config_file} and add your bot token" }
          Log.error { "[Gateway] Get a bot token from @BotFather on Telegram" }
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
    end
  end
end
