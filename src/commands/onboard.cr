require "log"

module Crybot
  module Commands
    class Onboard
      def self.execute : Nil
        Log.info { "Initializing Crybot..." }

        Config::Loader.ensure_directories
        Config::Loader.create_default_config

        # Create default workspace files
        create_agents_md
        create_soul_md
        create_user_md
        create_tools_md
        create_memory_md

        Log.info { "✓ Configuration created at #{Config::Loader.config_file}" }
        Log.info { "✓ Workspace created at #{Config::Loader.workspace_dir}" }
        Log.info { "" }
        Log.info { "Next steps:" }
        Log.info { "1. Edit #{Config::Loader.config_file} to add your API keys" }
        Log.info { "2. For z.ai GLM models, add your key to providers.zhipu.api_key" }
        Log.info { "3. Run 'crybot status' to verify your configuration" }
        Log.info { "4. Run 'crybot agent' to start chatting" }
      end

      private def self.create_agents_md : Nil
        path = Config::Loader.workspace_dir / "AGENTS.md"
        return if File.exists?(path)

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
        return if File.exists?(path)

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
        return if File.exists?(path)

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
        return if File.exists?(path)

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
        return if File.exists?(path)

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
