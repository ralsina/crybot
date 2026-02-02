require "yaml"

module Crybot
  module Config
    struct AgentsConfig
      include YAML::Serializable

      property defaults : Defaults

      struct Defaults
        include YAML::Serializable

        property model : String = "glm-4.7-flash"
        property max_tokens : Int32 = 8192
        property temperature : Float64 = 0.7
        property max_tool_iterations : Int32 = 20
      end
    end

    struct ProvidersConfig
      include YAML::Serializable

      property zhipu : ZhipuConfig?
      property openai : OpenAIConfig?
      property anthropic : AnthropicConfig?
      property openrouter : OpenRouterConfig?
      property vllm : VLLMConfig?

      def zhipu : ZhipuConfig
        @zhipu ||= ZhipuConfig.new
      end

      def openai : OpenAIConfig
        @openai ||= OpenAIConfig.new
      end

      def anthropic : AnthropicConfig
        @anthropic ||= AnthropicConfig.new
      end

      def openrouter : OpenRouterConfig
        @openrouter ||= OpenRouterConfig.new
      end

      def vllm : VLLMConfig
        @vllm ||= VLLMConfig.new
      end

      struct ZhipuConfig
        include YAML::Serializable

        property api_key : String = ""

        def initialize(@api_key = "")
        end
      end

      struct OpenAIConfig
        include YAML::Serializable

        property api_key : String = ""

        def initialize(@api_key = "")
        end
      end

      struct AnthropicConfig
        include YAML::Serializable

        property api_key : String = ""

        def initialize(@api_key = "")
        end
      end

      struct OpenRouterConfig
        include YAML::Serializable

        property api_key : String = ""

        def initialize(@api_key = "")
        end
      end

      struct VLLMConfig
        include YAML::Serializable

        property api_key : String = ""
        property api_base : String = ""

        def initialize(@api_key = "", @api_base = "")
        end
      end
    end

    struct ChannelsConfig
      include YAML::Serializable

      property telegram : TelegramConfig

      struct TelegramConfig
        include YAML::Serializable

        # ameba:disable Naming/QueryBoolMethods
        property enabled : Bool = false
        property token : String = ""
        property allow_from : Array(String) = [] of String
      end
    end

    struct ToolsConfig
      include YAML::Serializable

      property web : WebConfig

      struct WebConfig
        include YAML::Serializable

        property search : SearchConfig

        struct SearchConfig
          include YAML::Serializable

          property api_key : String = ""
          property max_results : Int32 = 5
        end
      end
    end

    struct MCPConfig
      include YAML::Serializable

      property servers : Array(MCPServerConfig) = [] of MCPServerConfig

      def initialize(@servers = [] of MCPServerConfig)
      end
    end

    struct MCPServerConfig
      include YAML::Serializable

      property name : String
      property command : String?
      property url : String?
    end

    struct ConfigFile
      include YAML::Serializable

      property agents : AgentsConfig
      property providers : ProvidersConfig
      property channels : ChannelsConfig
      property tools : ToolsConfig
      property mcp : MCPConfig = MCPConfig.new(servers: [] of MCPServerConfig)
    end
  end
end
