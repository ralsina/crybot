require "../config/loader"
require "../channels/slack_channel"
require "./base"

module Crybot
  module Features
    class SlackFeature < FeatureModule
      @config : Config::ConfigFile
      @agent : Agent::Loop?
      @slack_channel : Channels::SlackChannel?
      @client_fiber : Fiber?

      def initialize(@config : Config::ConfigFile)
      end

      def start : Nil
        return unless validate_config(@config)

        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting Slack feature..."

        # Create agent loop
        @agent = Agent::Loop.new(@config)

        # Create Slack channel
        slack_config = @config.channels.slack
        @slack_channel = Channels::SlackChannel.new(slack_config, @agent)

        # Register with unified registry for scheduled task forwarding
        Channels::UnifiedRegistry.register(@slack_channel)

        # Start the Slack client in a fiber so we don't block
        slack_channel = @slack_channel
        if slack_channel
          @client_fiber = spawn do
            begin
              slack_channel.start
            rescue e : Exception
              puts "[Slack] Error in client fiber: #{e.message}"
              puts e.backtrace.join("\n") if ENV["DEBUG"]?
            end
          end
        end

        @running = true
        puts "[#{Time.local.to_s("%H:%M:%S")}] Slack feature started"
      end

      def stop : Nil
        @running = false
        if slack_channel = @slack_channel
          slack_channel.stop
        end
        puts "[#{Time.local.to_s("%H:%M:%S")}] Slack feature stopped"
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check if Slack is enabled
        slack_config = config.channels.slack
        unless slack_config.enabled?
          puts "Slack feature is disabled in configuration."
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

        # Check Slack tokens
        if slack_config.socket_token.empty? && ENV["SLACK_SOCKET_TOKEN"]?.nil?
          puts "Error: Slack enabled but socket token not configured."
          puts "Please edit #{Config::Loader.config_file} and add your socket token:"
          puts "  channels.slack.socket_token: \"xapp-...\""
          puts "\nOr set the SLACK_SOCKET_TOKEN environment variable."
          puts "\nGet a socket token from https://api.slack.com/apps"
          return false
        end

        if slack_config.api_token.empty? && ENV["SLACK_API_TOKEN"]?.nil?
          puts "Error: Slack enabled but API token not configured."
          puts "Please edit #{Config::Loader.config_file} and add your API token:"
          puts "  channels.slack.api_token: \"xoxb-...\""
          puts "\nOr set the SLACK_API_TOKEN environment variable."
          puts "\nGet an API token from https://api.slack.com/apps"
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
