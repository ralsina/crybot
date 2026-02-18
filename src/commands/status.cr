require "log"
require "../config/loader"

module Crybot
  module Commands
    class Status
      def self.execute : Nil
        Log.info { "Crybot Status" }
        Log.info { "=" * 40 }

        # Check config file
        if File.exists?(Config::Loader.config_file)
          Log.info { "✓ Config file: #{Config::Loader.config_file}" }
          config = Config::Loader.load

          # Check providers
          Log.info { "" }
          Log.info { "Providers:" }
          check_provider("z.ai / Zhipu", config.providers.zhipu.api_key)

          # Check channels
          Log.info { "" }
          Log.info { "Channels:" }
          if config.channels.telegram.enabled?
            if config.channels.telegram.token.empty?
              Log.warn { "  Telegram: configured but missing token" }
            else
              Log.info { "  ✓ Telegram: enabled" }
            end
          else
            Log.info { "  Telegram: disabled" }
          end

          # Check tools
          Log.info { "" }
          Log.info { "Tools:" }
          if config.tools.web.search.api_key.empty?
            Log.info { "  Web Search: not configured (optional)" }
          else
            Log.info { "  ✓ Web Search: configured" }
          end

          # Default agent settings
          Log.info { "" }
          Log.info { "Default Agent Settings:" }
          Log.info { "  Model: #{config.agents.defaults.model}" }
          Log.info { "  Max tokens: #{config.agents.defaults.max_tokens}" }
          Log.info { "  Temperature: #{config.agents.defaults.temperature}" }
          Log.info { "  Max tool iterations: #{config.agents.defaults.max_tool_iterations}" }
        else
          Log.error { "✗ Config file not found: #{Config::Loader.config_file}" }
          Log.info { "" }
          Log.info { "Run 'crybot onboard' to initialize." }
          return
        end

        # Check workspace
        Log.info { "" }
        Log.info { "Workspace:" }
        Log.info { "  ✓ Config dir: #{Config::Loader.config_dir}" }
        Log.info { "  ✓ Workspace: #{Config::Loader.workspace_dir}" }
        Log.info { "  ✓ Sessions: #{Config::Loader.sessions_dir}" }
        Log.info { "  ✓ Memory: #{Config::Loader.memory_dir}" }
        Log.info { "  ✓ Skills: #{Config::Loader.skills_dir}" }

        # Check workspace files
        workspace_files = [
          {"AGENTS.md", "Agent configuration"},
          {"SOUL.md", "Core behavior"},
          {"USER.md", "User preferences"},
          {"TOOLS.md", "Tool documentation"},
        ]

        Log.info { "" }
        Log.info { "Workspace Files:" }
        workspace_files.each do |(file, description)|
          path = Config::Loader.workspace_dir / file
          if File.exists?(path)
            Log.info { "  ✓ #{file} - #{description}" }
          else
            Log.warn { "  ✗ #{file} - missing" }
          end
        end

        # Session count
        sessions = Dir.children(Config::Loader.sessions_dir)
        Log.info { "" }
        Log.info { "Sessions: #{sessions.size} saved" }
      end

      private def self.check_provider(name : String, api_key : String) : Nil
        if api_key.empty?
          Log.warn { "  #{name}: not configured" }
        else
          Log.info { "  ✓ #{name}: configured" }
        end
      end
    end
  end
end
