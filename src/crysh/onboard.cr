module Crybot
  module Crysh
    class Onboard
      def self.execute : Nil
        puts "🚀 Welcome to Crysh!"
        puts ""
        puts "Crysh is a natural language shell wrapper that generates"
        puts "shell commands from your descriptions using LLMs."
        puts ""

        # Check if crybot config exists
        config_file = Path.home / ".crybot" / "workspace" / "config.yml"

        if File.exists?(config_file)
          puts "✓ Configuration found at #{config_file}"
          puts ""
          config = YAML.parse(File.read(config_file))
          provider = config["agents"]["defaults"]["provider"].as_s
          model = config["agents"]["defaults"]["model"].as_s

          # Check if API key is configured
          providers = config["providers"]?
          has_key = false
          if providers && providers[provider]?
            api_key = providers[provider]["api_key"].as_s
            has_key = !api_key.empty?
          end

          if has_key
            puts "✓ Provider configured: #{provider} (#{model})"
            puts ""
            puts "You're all set! Try it out:"
            puts "  crysh sort by size"
            puts "  crysh count unique lines"
            puts "  crysh get the second field"
            puts ""
            return
          else
            puts "⚠️  Config exists but no API key found for #{provider}"
            puts ""
            reconfigure = get_input("Configure API key now? (Y/n): ", "y").downcase
            return unless reconfigure == "y" || reconfigure.empty?
            puts ""
          end
        end

        # No config found, need to set up
        prompt_api_keys
      end

      private def self.get_input(prompt : String, default : String = "") : String
        STDOUT.flush
        print prompt
        STDOUT.flush
        input = gets
        return default unless input
        input.strip
      end

      private def self.puts(msg : String) : Nil
        ::puts msg
      end

      private def self.prompt_api_keys : Nil
        puts ""
        puts "🔑 API Key Configuration"
        puts ""
        puts "Crysh uses the same configuration as Crybot."
        puts "Available providers (recommendations for fast command generation):"
        puts ""
        puts "  1. OpenRouter (stepfun/step-3.5-flash:free - FREE & fast)"
        puts "  2. Groq (llama models - FREE & very fast)"
        puts "  3. Zhipu GLM (glm-4.7-flash - FREE tier)"
        puts "  4. OpenAI (GPT-4o-mini - fast & cheap)"
        puts "  5. Anthropic (Claude Haiku - fast & cheap)"
        puts ""

        # Ensure config directory exists
        config_dir = Path.home / ".crybot" / "workspace"
        Dir.mkdir_p(config_dir)

        config_file = config_dir / "config.yml"

        # Create default config if it doesn't exist
        unless File.exists?(config_file)
          default_config = <<-YAML
          ---
          agents:
            defaults:
              provider: openrouter
              model: stepfun/step-3.5-flash:free
              max_tokens: 8192
              temperature: 0.7
              max_tool_iterations: 20

          providers:
            zhipu:
              api_key: ""
            openrouter:
              api_key: ""
            groq:
              api_key: ""
            openai:
              api_key: ""
            anthropic:
              api_key: ""
          YAML

          File.write(config_file, default_config)
          puts "✓ Created configuration at #{config_file}"
        end

        puts ""
        puts "Enter API keys (press Enter to skip):"
        puts ""

        # Prompt for each provider
        providers = {
          "openrouter" => "OpenRouter (recommended - free stepfun model)",
          "groq"       => "Groq (very fast - free llama models)",
          "zhipu"      => "Zhipu GLM (free tier available)",
          "openai"     => "OpenAI (GPT models)",
          "anthropic"  => "Anthropic (Claude models)",
        }

        providers.each do |key, description|
          print "#{description}\nAPI key: "
          STDOUT.flush
          api_key = gets.try(&.strip) || ""

          if !api_key.empty?
            update_api_key(config_file, key, api_key)
            puts "✓ Saved #{key} API key"
            puts ""

            # Set as default if first key entered
            set_default_provider(config_file, key) if key == "openrouter" || key == "groq"
          end
        end

        puts ""
        puts "✅ Setup complete!"
        puts ""
        puts "Configuration: #{config_file}"
        puts ""
        puts "Try it out:"
        puts "  crysh sort by size"
        puts "  crysh count unique lines"
        puts "  crysh get the second field"
        puts ""
        puts "Options:"
        puts "  crysh -y 'command'  # Skip confirmation"
        puts "  crysh --dry-run ... # Preview command"
        puts "  crysh -v ...        # Verbose logging"
        puts ""
      end

      private def self.update_api_key(config_file : Path, provider : String, key : String) : Nil
        config_content = File.read(config_file)

        # Simple regex replacement for api_key
        pattern = /#{provider}:\s*\n\s*api_key:\s*"[^"]*"/
        replacement = "#{provider}:\n  api_key: \"#{key}\""

        config_content = config_content.gsub(pattern, replacement)

        File.write(config_file, config_content)
      end

      private def self.set_default_provider(config_file : Path, provider : String) : Nil
        config_content = File.read(config_file)

        # Update provider and model
        config_content = config_content.gsub(
          /provider:\s*\S+/,
          "provider: #{provider}"
        )

        # Set recommended model based on provider
        model_map = {
          "openrouter" => "stepfun/step-3.5-flash:free",
          "groq"       => "llama-3.3-8b-it", # or whatever groq's fast model is
          "zhipu"      => "glm-4.7-flash",
        }

        if model = model_map[provider]?
          config_content = config_content.gsub(
            /model:\s*\S+/,
            "model: #{model}"
          )
        end

        File.write(config_file, config_content)
      end
    end
  end
end
