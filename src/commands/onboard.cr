require "file_utils"

module Crybot
  module Commands
    class Onboard
      def self.execute : Nil
        puts "🚀 Welcome to Crybot!"
        puts ""

        # Check if already configured
        if File.exists?(Config::Loader.config_file)
          puts "⚠️  Configuration already exists at #{Config::Loader.config_file}"
          reconfigure = get_input("Do you want to reconfigure? (y/N): ").downcase
          return unless reconfigure == "y" || reconfigure == "yes"
          puts ""
        end

        # Ensure directories exist
        Config::Loader.ensure_directories
        Config::Loader.create_default_config

        # Interactive prompts
        prompt_api_keys
        prompt_systemd_service

        # Create default workspace files
        create_agents_md
        create_soul_md
        create_user_md
        create_tools_md
        create_memory_md

        puts ""
        puts "✅ Setup complete!"
        puts ""
        puts "Configuration: #{Config::Loader.config_file}"
        puts "Workspace: #{Config::Loader.workspace_dir}"
        puts ""
        puts "Next steps:"
        puts "1. Edit #{Config::Loader.config_file} to add more API keys"
        puts "2. Run 'crybot status' to verify your configuration"
        puts "3. Run 'crybot start' to begin"
        puts ""

        # Ask if user wants to start now
        if service_enabled?
          start_now = get_input("Would you like to start Crybot now? (Y/n): ", "y").downcase
          if start_now == "y" || start_now.empty?
            puts "Starting Crybot..."
            puts "Run: crybot start"
          end
        end
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
        puts "Crybot supports multiple LLM providers. You can configure them now or skip."
        puts ""
        puts "Available providers:"
        puts "  1. Zhipu GLM (free tier available)"
        puts "  2. OpenAI (GPT-4, GPT-4o)"
        puts "  3. Anthropic (Claude)"
        puts "  4. OpenRouter (100+ models)"
        puts ""
        configure_keys = get_input("Configure API keys now? (Y/n): ", "y").downcase

        return unless configure_keys == "y" || configure_keys.empty?

        puts ""

        # Zhipu GLM
        zhipu_key = get_input("Enter Zhipu API key (or press Enter to skip): ")
        if !zhipu_key.empty?
          update_api_key("zhipu", zhipu_key)
          puts "✓ Zhipu API key configured"
        end

        # OpenAI
        openai_key = get_input("Enter OpenAI API key (or press Enter to skip): ")
        if !openai_key.empty?
          update_api_key("openai", openai_key)
          puts "✓ OpenAI API key configured"
        end

        # Anthropic
        anthropic_key = get_input("Enter Anthropic API key (or press Enter to skip): ")
        if !anthropic_key.empty?
          update_api_key("anthropic", anthropic_key)
          puts "✓ Anthropic API key configured"
        end

        # OpenRouter
        openrouter_key = get_input("Enter OpenRouter API key (or press Enter to skip): ")
        if !openrouter_key.empty?
          update_api_key("openrouter", openrouter_key)
          puts "✓ OpenRouter API key configured"
        end

        puts ""
        puts "✅ API key configuration complete!"
        puts "You can add more keys later by editing #{Config::Loader.config_file}"
      end

      private def self.update_api_key(provider : String, key : String) : Nil
        config_content = File.read(Config::Loader.config_file)

        # Check if provider section exists
        if config_content.includes?("#{provider}:")
          # Replace existing key
          config_content = config_content.gsub(/#{provider}:\s*\n\s*api_key:\s*"[^"]*"/, "#{provider}:\n  api_key: \"#{key}\"")
        else
          # Add provider section
          lines = config_content.lines
          insert_at = -1
          lines.each_with_index do |line, index|
            if line.includes?("providers:")
              insert_at = index + 1
              break
            end
          end

          if insert_at > 0
            lines.insert(insert_at, "  #{provider}:\n    api_key: \"#{key}\"")
            config_content = lines.join('\n')
          end
        end

        File.write(Config::Loader.config_file, config_content)
      end

      private def self.prompt_systemd_service : Nil
        puts ""
        puts "⚙️  Systemd Service Configuration"
        puts ""
        puts "Crybot can run as a systemd user service for auto-startup."
        puts ""
        puts "Options:"
        puts "  1. Start when I log in (user service)"
        puts "  2. Run 24/7 even when logged out (auto service)"
        puts "  3. Skip, I'll start it manually"
        puts ""
        choice = get_input("Choose an option [1-3] (default: 3): ", "3")

        service_choice = case choice
                         when "1", "user" then "user"
                         when "2", "auto" then "auto"
                         else                  "" # default
                         end

        if !service_choice.empty?
          create_systemd_service(service_choice)
        end
      end

      private def self.create_systemd_service(service_type : String) : Nil
        systemd_dir = Path.home / ".config" / "systemd" / "user"
        service_file = systemd_dir / "crybot.service"

        # Ensure directory exists
        Dir.mkdir_p(systemd_dir)

        # Get crybot path
        crybot_path = `which crybot`.strip.chomp

        service_content = <<-INI
        [Unit]
        Description=Crybot AI Assistant
        After=network.target

        [Service]
        Type=simple
        ExecStart=#{crybot_path} start
        Restart=on-failure
        RestartSec=5

        [Install]
        WantedBy=default.target
        INI

        File.write(service_file, service_content)

        # Enable and start service
        puts ""
        puts "Enabling Crybot service..."

        system("systemctl --user daemon-reload")
        system("systemctl --user enable crybot.service")

        if service_type == "auto"
          puts "Enabling 24/7 operation..."
          system("loginctl enable-linger $USER")
        end

        puts "Starting Crybot service..."
        system("systemctl --user start crybot.service")

        puts "✓ Systemd service created and started!"

        puts ""
        puts "Service management:"
        puts "  systemctl --user status crybot.service   # Check status"
        puts "  systemctl --user stop crybot.service    # Stop service"
        puts "  systemctl --user restart crybot.service # Restart service"
        puts "  journalctl --user -u crybot.service -f  # View logs"

        if service_type == "auto"
          puts ""
          puts "Crybot will now run 24/7, even when you're logged out."
        else
          puts ""
          puts "Crybot will start automatically when you log in."
        end
      end

      private def self.service_enabled? : Bool
        service_file = Path.home / ".config" / "systemd" / "user" / "crybot.service"
        File.exists?(service_file)
      end

      private def self.create_agents_md : Nil
        path = Config::Loader.workspace_dir / "AGENTS.md"
        return if File.info?(path)

        content = <<-MD
        # Agent Configuration

        This file defines how the AI agent should behave.

        ## Identity

        You are Crybot, a personal AI assistant built in Crystal. You are helpful, capable, and efficient.

        ## Core Principles

        - Be concise and direct in your responses
        - Use tools when they would be more efficient than manual work
        - Always verify file paths before operations
        - Ask for clarification when tasks are ambiguous

        ## Tool Usage

        - Use `read_file` to examine files before editing
        - Use `write_file` for new file creation
        - Use `edit_file` for targeted modifications
        - Use `list_dir` to explore directory structures
        - Use `exec` for shell commands when necessary
        - Use `web_search` and `web_fetch` for online information
        MD

        File.write(path, content)
      end

      private def self.create_soul_md : Nil
        path = Config::Loader.workspace_dir / "SOUL.md"
        return if File.info?(path)

        content = <<-MD
        # SOUL - Core Agent Behavior

        This file contains the deepest behavioral instructions for the agent.

        ## Tone and Style

        - Professional but approachable
        - Technical explanations should be clear and accurate
        - Admit when you don't know something
        - Provide context for complex topics

        ## Decision Making

        - Prefer explicit actions over vague suggestions
        - Consider security implications (no malicious commands)
        - Respect user data and privacy

        ## Learning

        - Store important information in memory/MEMORY.md
        - Reference previous context when relevant
        MD

        File.write(path, content)
      end

      private def self.create_user_md : Nil
        path = Config::Loader.workspace_dir / "USER.md"
        return if File.info?(path)

        content = <<-MD
        # User Preferences

        This file contains user-specific preferences and instructions.

        ## Preferences

        - Add your custom preferences here
        - Include communication style preferences
        - Note any specific requirements or constraints

        ## Examples

        - Preferred programming languages
        - Documentation style preferences
        - Project-specific conventions
        MD

        File.write(path, content)
      end

      private def self.create_tools_md : Nil
        path = Config::Loader.workspace_dir / "TOOLS.md"
        return if File.info?(path)

        content = <<-MD
        # Available Tools

        ## File System

        - `read_file(path)` - Read file contents
        - `write_file(path, content)` - Write/create a file
        - `edit_file(path, old_content, new_content, count)` - Replace text in a file
        - `list_dir(path)` - List directory contents

        ## Shell

        - `exec(command, timeout)` - Execute a shell command with timeout

        ## Web

        - `web_search(query, max_results)` - Search the web using Brave Search API
        - `web_fetch(url)` - Fetch and read a web page
        MD

        File.write(path, content)
      end

      private def self.create_memory_md : Nil
        path = Config::Loader.memory_dir / "MEMORY.md"
        return if File.info?(path)

        content = <<-MD
        # Agent Memory

        This file stores persistent information for the agent.

        ## Important Context

        Add important information here that should persist between conversations.

        ## Project Notes

        - Track project-specific information here
        - Remember user preferences and conventions
        MD

        File.write(path, content)
      end
    end
  end
end
