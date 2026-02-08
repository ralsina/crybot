require "../web/server"
require "./base"

module Crybot
  module Features
    class WebFeature < FeatureModule
      @config : Config::ConfigFile
      @server : Web::Server?
      @server_fiber : Fiber?
      @agent_loop : Agent::Loop?

      def initialize(@config : Config::ConfigFile)
      end

      def start(@agent_loop : Agent::Loop? = nil) : Nil
        return unless validate_config(@config)

        # Use provided agent loop or create a new one
        agent = @agent_loop || Agent::Loop.new(@config)
        @agent_loop = agent

        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting web feature..."
        puts "[#{Time.local.to_s("%H:%M:%S")}] Listening on http://#{@config.web.host}:#{@config.web.port}"

        # Create server instance with existing agent loop
        @server = Web::Server.new(@config, agent)

        # Start Kemal in a fiber
        @server_fiber = spawn do
          @server.try(&.start)
        end

        @running = true
      end

      def stop : Nil
        @running = false
        # Kemal doesn't have a built-in stop method, so we set running flag
        # The server will need to be terminated via signal handling
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider(model)

        case provider
        when "openai"
          if config.providers.openai.api_key.empty?
            puts "Warning: OpenAI API key not configured."
          end
        when "anthropic"
          if config.providers.anthropic.api_key.empty?
            puts "Warning: Anthropic API key not configured."
          end
        when "openrouter"
          if config.providers.openrouter.api_key.empty?
            puts "Warning: OpenRouter API key not configured."
          end
        when "vllm"
          if config.providers.vllm.api_base.empty?
            puts "Warning: vLLM api_base not configured."
          end
        else # zhipu (default)
          if config.providers.zhipu.api_key.empty?
            puts "Warning: z.ai API key not configured."
          end
        end

        # Warn if no auth token configured
        if config.web.auth_token.empty?
          puts "Warning: No auth_token configured. Web UI will be accessible without authentication."
          puts "Set web.auth_token in #{Config::Loader.config_file} to enable authentication."
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
