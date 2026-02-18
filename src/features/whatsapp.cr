require "../config/loader"
require "../channels/whatsapp_channel"
require "./base"

module Crybot
  module Features
    class WhatsAppFeature < FeatureModule
      @config : Config::ConfigFile
      @agent : Agent::Loop?
      @whatsapp_channel : Channels::WhatsAppChannel?

      def initialize(@config : Config::ConfigFile)
      end

      def start : Nil
        return unless validate_config(@config)

        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting WhatsApp feature..."

        # Create agent loop
        @agent = Agent::Loop.new(@config)

        # Create WhatsApp channel
        whatsapp_config = @config.channels.whatsapp
        @whatsapp_channel = Channels::WhatsAppChannel.new(whatsapp_config, @agent)

        # Register with unified registry for scheduled task forwarding
        Channels::UnifiedRegistry.register(@whatsapp_channel)

        @whatsapp_channel.start

        @running = true
        puts "[#{Time.local.to_s("%H:%M:%S")}] WhatsApp feature started"
      end

      def stop : Nil
        @running = false
        if whatsapp_channel = @whatsapp_channel
          whatsapp_channel.stop
        end
        puts "[#{Time.local.to_s("%H:%M:%S")}] WhatsApp feature stopped"
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def validate_config(config : Config::ConfigFile) : Bool
        # Check if WhatsApp is enabled
        whatsapp_config = config.channels.whatsapp
        unless whatsapp_config.enabled?
          puts "WhatsApp feature is disabled in configuration."
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

        # Check WhatsApp Cloud API credentials
        if whatsapp_config.phone_number_id.empty?
          puts "Error: WhatsApp enabled but phone_number_id not configured."
          puts "Please edit #{Config::Loader.config_file} and add your Phone Number ID:"
          puts "  channels.whatsapp.phone_number_id: \"123456789\""
          puts ""
          puts "Get your Phone Number ID from:"
          puts "  https://developers.facebook.com/apps/"
          puts "  > Select your app > WhatsApp > API Setup"
          return false
        end

        if whatsapp_config.access_token.empty?
          puts "Error: WhatsApp enabled but access_token not configured."
          puts "Please edit #{Config::Loader.config_file} and add your Access Token:"
          puts "  channels.whatsapp.access_token: \"your_access_token\""
          puts ""
          puts "Get your Access Token from:"
          puts "  https://developers.facebook.com/apps/"
          puts "  > Select your app > WhatsApp > API Setup"
          return false
        end

        if whatsapp_config.webhook_verify_token.empty?
          puts "Error: WhatsApp enabled but webhook_verify_token not configured."
          puts "Please edit #{Config::Loader.config_file} and add a verify token:"
          puts "  channels.whatsapp.webhook_verify_token: \"your_secret_token\""
          puts ""
          puts "Choose any string - you'll need to configure this in Meta's dashboard."
          return false
        end

        if whatsapp_config.app_secret.empty?
          puts "Error: WhatsApp enabled but app_secret not configured."
          puts "Please edit #{Config::Loader.config_file} and add your App Secret:"
          puts "  channels.whatsapp.app_secret: \"your_app_secret\""
          puts ""
          puts "Get your App Secret from:"
          puts "  https://developers.facebook.com/apps/"
          puts "  > Select your app > Settings > Basic"
          return false
        end

        # Web feature must be enabled for WhatsApp to work (webhooks)
        unless config.features.web
          puts "Note: WhatsApp requires the web feature to be enabled for webhooks."
          puts "The web feature handles incoming WhatsApp messages."
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
