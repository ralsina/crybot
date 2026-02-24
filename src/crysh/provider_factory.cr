require "../providers/*"

module Crybot
  module Crysh
    module ProviderFactory
      # ameba:disable Metrics/CyclomaticComplexity
      def self.create_provider(config : Config::ConfigFile) : Providers::LLMProvider
        provider_name = config.agents.defaults.provider
        model = config.agents.defaults.model

        case provider_name
        when "openai"
          api_key = config.providers.openai.api_key
          raise "OpenAI API key not configured" if api_key.empty?
          Providers::OpenAIProvider.new(api_key, model)
        when "anthropic"
          api_key = config.providers.anthropic.api_key
          raise "Anthropic API key not configured" if api_key.empty?
          Providers::AnthropicProvider.new(api_key, model)
        when "openrouter"
          api_key = config.providers.openrouter.api_key
          raise "OpenRouter API key not configured" if api_key.empty?
          Providers::OpenRouterProvider.new(api_key, model)
        when "groq"
          api_key = config.providers.groq.api_key
          raise "Groq API key not configured" if api_key.empty?
          Providers::GroqProvider.new(api_key, model)
        when "gemini"
          api_key = config.providers.gemini.api_key
          raise "Gemini API key not configured" if api_key.empty?
          Providers::GeminiProvider.new(api_key, model)
        when "deepseek"
          api_key = config.providers.deepseek.api_key
          raise "DeepSeek API key not configured" if api_key.empty?
          Providers::DeepSeekProvider.new(api_key, model)
        when "vllm"
          api_base = config.providers.vllm.api_base
          raise "vLLM api_base not configured" if api_base.empty?
          Providers::VLLMProvider.new(config.providers.vllm.api_key, api_base, model)
        else
          # Default to Zhipu
          api_key = config.providers.zhipu.api_key
          raise "Zhipu API key not configured" if api_key.empty?
          Providers::ZhipuProvider.new(api_key, model)
        end
      end
    end
  end
end
