require "log"
require "../config/loader"
require "../web/server"
require "../web/handlers/logs_handler"

module Crybot
  module Commands
    class Web
      def self.execute(port_override : Int32?) : Nil
        new.run(port_override)
      end

      def run(port_override : Int32?) : Nil
        config = Config::Loader.load
        return unless validate_config(config)

        # Apply port override if provided
        if port_override
          config = config.with_web(config.web.with_port(port_override))
        end

        Log.info { "[#{Time.local.to_s("%H:%M:%S")}] Starting Crybot Web Server..." }
        Log.info { "[#{Time.local.to_s("%H:%M:%S")}] Listening on http://#{config.web.host}:#{config.web.port}" }
        # TODO: Fix logging - commented out for now
        # Crybot::Web::Handlers::LogsHandler.log("INFO", "Web server started on http://#{config.web.host}:#{config.web.port}")

        server = Crybot::Web::Server.new(config)
        server.start
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider(model)

        case provider
        when "openai"
          if config.providers.openai.api_key.empty?
            Log.warn { "Warning: OpenAI API key not configured." }
          end
        when "anthropic"
          if config.providers.anthropic.api_key.empty?
            Log.warn { "Warning: Anthropic API key not configured." }
          end
        when "openrouter"
          if config.providers.openrouter.api_key.empty?
            Log.warn { "Warning: OpenRouter API key not configured." }
          end
        when "vllm"
          if config.providers.vllm.api_base.empty?
            Log.warn { "Warning: vLLM api_base not configured." }
          end
        else # zhipu (default)
          if config.providers.zhipu.api_key.empty?
            Log.warn { "Warning: z.ai API key not configured." }
          end
        end

        # Warn if no auth token configured
        if config.web.auth_token.empty?
          Log.warn { "Warning: No auth_token configured. Web UI will be accessible without authentication." }
          Log.warn { "Set web.auth_token in #{Config::Loader.config_file} to enable authentication." }
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
