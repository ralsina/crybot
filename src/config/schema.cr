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

      property web : ToolsWebConfig

      struct ToolsWebConfig
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

    struct VoiceConfig
      include YAML::Serializable

      property wake_word : String? = nil
      property whisper_stream_path : String? = nil
      property model_path : String? = nil
      property language : String? = nil
      property threads : Int32? = nil
      property piper_model : String? = nil
      property piper_path : String? = nil
      property conversational_timeout : Int32? = nil

      def initialize(@wake_word = nil, @whisper_stream_path = nil, @model_path = nil, @language = nil, @threads = nil, @piper_model = nil, @piper_path = nil, @conversational_timeout = nil)
      end
    end

    struct WebServerConfig
      include YAML::Serializable

      @[YAML::Field(key: "enabled")]
      property? enabled : Bool = false
      property host : String = "127.0.0.1"
      property port : Int32 = 3000
      property path_prefix : String = ""
      property auth_token : String = ""
      property allowed_origins : Array(String) = ["http://localhost:3000"]
      @[YAML::Field(key: "enable_cors")]
      property? enable_cors : Bool = true

      def initialize(@enabled = false, @host = "127.0.0.1", @port = 3000, @path_prefix = "", @auth_token = "", @allowed_origins = ["http://localhost:3000"], @enable_cors = true)
      end

      def with_port(@port : Int32) : WebServerConfig
        self
      end

      def with_enabled(@enabled : Bool) : WebServerConfig
        self
      end

      def with_host(@host : String) : WebServerConfig
        self
      end

      def with_auth_token(@auth_token : String) : WebServerConfig
        self
      end
    end

    struct ConfigFile
      include YAML::Serializable

      property agents : AgentsConfig
      property providers : ProvidersConfig
      property channels : ChannelsConfig
      property tools : ToolsConfig
      property mcp : MCPConfig = MCPConfig.new(servers: [] of MCPServerConfig)
      property voice : VoiceConfig? = nil
      property web : WebServerConfig = WebServerConfig.new

      def with_web(@web : WebServerConfig) : ConfigFile
        self
      end
    end
  end
end
