require "file_utils"
require "./schema"

module Crybot
  module Config
    class Loader
      CONFIG_DIR = Path.home / ".crybot"
      # config.yml is now in workspace/ so the agent can modify it
      CONFIG_FILE   = CONFIG_DIR / "workspace" / "config.yml"
      WORKSPACE_DIR = CONFIG_DIR / "workspace"
      SESSIONS_DIR  = CONFIG_DIR / "sessions"
      MEMORY_DIR    = WORKSPACE_DIR / "memory"
      SKILLS_DIR    = WORKSPACE_DIR / "skills"

      @@config : ConfigFile?

      def self.config_dir : Path
        CONFIG_DIR
      end

      def self.config_file : Path
        CONFIG_FILE
      end

      def self.workspace_dir : Path
        WORKSPACE_DIR
      end

      def self.sessions_dir : Path
        SESSIONS_DIR
      end

      def self.memory_dir : Path
        MEMORY_DIR
      end

      def self.skills_dir : Path
        SKILLS_DIR
      end

      def self.load : ConfigFile
        cached = @@config
        return cached unless cached.nil?

        # Migrate config.yml from old location (.crybot/config.yml) to new location (.crybot/workspace/config.yml)
        old_config_file = CONFIG_DIR / "config.yml"
        if File.exists?(old_config_file) && !File.exists?(CONFIG_FILE)
          puts "[Config] Migrating config.yml to workspace/ directory..."
          Dir.mkdir_p(WORKSPACE_DIR) unless Dir.exists?(WORKSPACE_DIR)
          File.rename(old_config_file, CONFIG_FILE)
        end

        unless File.exists?(CONFIG_FILE)
          raise "Config file not found: #{CONFIG_FILE}. Run 'crybot onboard' to initialize."
        end

        content = File.read(CONFIG_FILE)
        result = ConfigFile.from_yaml(content)
        @@config = result
        result
      end

      def self.reload : ConfigFile
        @@config = nil
        load
      end

      def self.migrate_config(config : ConfigFile) : ConfigFile
        needs_migration = false
        new_features = config.features

        # Migrate old channels.telegram.enabled to features.gateway
        if config.channels.telegram.enabled? && !config.features.gateway
          new_features = new_features.with_gateway(true)
          needs_migration = true
        end

        # Migrate old web.enabled to features.web
        if config.web.enabled? && !config.features.web
          new_features = new_features.with_web(true)
          needs_migration = true
        end

        if needs_migration
          config = config.with_features(new_features)
        end

        config
      end

      def self.ensure_directories : Nil
        Dir.mkdir_p(CONFIG_DIR) unless Dir.exists?(CONFIG_DIR)
        Dir.mkdir_p(WORKSPACE_DIR) unless Dir.exists?(WORKSPACE_DIR)
        Dir.mkdir_p(SESSIONS_DIR) unless Dir.exists?(SESSIONS_DIR)
        Dir.mkdir_p(MEMORY_DIR) unless Dir.exists?(MEMORY_DIR)
        Dir.mkdir_p(SKILLS_DIR) unless Dir.exists?(SKILLS_DIR)
      end

      def self.create_default_config : Nil
        return if File.exists?(CONFIG_FILE)

        default_config = <<-YAML
        agents:
          defaults:
            provider: zhipu
            model: glm-4.7-flash
            max_tokens: 8192
            temperature: 0.7
            max_tool_iterations: 20

        providers:
          zhipu:
            api_key: ""  # Get from https://open.bigmodel.cn/
          openai:
            api_key: ""  # Get from https://platform.openai.com/
          anthropic:
            api_key: ""  # Get from https://console.anthropic.com/
          openrouter:
            api_key: ""  # Get from https://openrouter.ai/
          groq:
            api_key: ""  # Get from https://console.groq.com/
            lite: true  # Set to false if using paid tier (lite mode disables tools/skills for free tier compatibility)
          gemini:
            api_key: ""  # Get from https://ai.google.dev/gemini-api/docs
          deepseek:
            api_key: ""  # Get from https://platform.deepseek.com/api_keys (5M free tokens for new users!)
          vllm:
            api_key: ""  # Often empty for local vLLM
            api_base: ""  # e.g., http://localhost:8000/v1

        channels:
          telegram:
            enabled: false
            token: ""
            allow_from: []

        tools:
          web:
            search:
              api_key: ""  # Brave Search API
              max_results: 5

        landlock:
          disabled: false  # Set to true to disable Landlock sandboxing (not recommended for production use)

        mcp:
          servers: []
          # Example MCP servers:
          # - name: filesystem
          #   command: npx -y @modelcontextprotocol/server-filesystem /path/to/allowed/directory
          # - name: github
          #   command: npx -y @modelcontextprotocol/server-github
          # - name: brave-search
          #   command: npx -y @modelcontextprotocol/server-brave-search

        features:
          gateway: false  # Enable Telegram gateway
          web: false      # Enable web UI server
          voice: false    # Enable voice listener
          repl: false     # Enable interactive REPL

        voice:
          wake_word: "crybot"
          whisper_stream_path: ""  # Auto-detect by default
          model_path: ""
          language: "en"
          threads: 4
          piper_model: ""  # Optional: path to piper TTS model
          piper_path: ""   # Optional: path to piper-tts binary
          conversational_timeout: 3
          # whisper-stream options:
          step_ms: 3000          # How often to transcribe (ms) - higher = less frequent updates
          audio_length_ms: 10000 # Audio length per chunk (ms)
          audio_keep_ms: 200     # Audio to keep from previous step (ms) - overlap for continuity
          vad_threshold: 0.6     # Voice activity detection (0.0-1.0) - higher = less sensitive

        web:
          enabled: false
          host: "127.0.0.1"
          port: 3003
          path_prefix: ""
          auth_token: ""  # Set to enable authentication
          allowed_origins:
            - "http://localhost:3003"
          enable_cors: true
        YAML

        File.write(CONFIG_FILE, default_config)
      end
    end
  end
end
