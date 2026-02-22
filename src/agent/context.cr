require "time"
require "../config/loader"
require "../providers/base"
require "./memory"
require "./skills"
require "./skill_manager"
require "./tools/registry"

module Crybot
  module Agent
    class ContextBuilder
      @config : Config::ConfigFile
      @workspace_dir : Path
      @memory_manager : MemoryManager
      @skill_manager : SkillManager
      @lite_mode : Bool

      def initialize(@config : Config::ConfigFile, @skill_manager : SkillManager, @lite_mode : Bool = false)
        @workspace_dir = Config::Loader.workspace_dir
        @memory_manager = MemoryManager.new(@workspace_dir)
      end

      def build_system_prompt : String
        parts = [] of String

        # Identity section (lite version when lite mode enabled)
        parts << build_identity_section

        # Bootstrap files and memory only when NOT in lite mode
        unless @lite_mode
          # Bootstrap files
          parts << build_bootstrap_section

          # Memory
          parts << build_memory_section
        end

        # Skills (only when NOT in lite mode)
        unless @lite_mode
          parts << build_skills_section
        end

        parts.compact.join("\n\n")
      end

      def build_messages(user_message : String, history : Array(Providers::Message), session_key : String? = nil) : Array(Providers::Message)
        messages = [] of Providers::Message

        # System prompt
        system_content = build_system_prompt

        # Add voice-friendly instructions if this is a voice session
        if session_key == "voice"
          puts "[Context] Adding voice instructions for session_key: #{session_key}"
          system_content += "\n\n" + build_voice_instructions
        end

        messages << Providers::Message.new("system", system_content)

        # Add history
        messages.concat(history)

        # Current user message
        messages << Providers::Message.new("user", user_message)

        messages
      end

      def add_tool_result(messages : Array(Providers::Message), tool_call : Providers::ToolCall, result : String) : Array(Providers::Message)
        messages << Providers::Message.new("tool", result, nil, tool_call.id, tool_call.name)
        messages
      end

      def add_assistant_message(messages : Array(Providers::Message), response : Providers::Response) : Array(Providers::Message)
        messages << Providers::Message.new("assistant", response.content, response.tool_calls)
        messages
      end

      # Record a memory entry from agent's actions
      def record_memory(content : String) : Nil
        @memory_manager.append_to_daily_log(content)
      end

      # Save a long-term memory entry
      def save_memory(content : String) : Nil
        @memory_manager.write(content)
      end

      # Get recent memories
      def get_recent_memories(days : Int32 = 7) : Array(String)
        @memory_manager.get_recent(days)
      end

      # Search memories
      def search_memories(query : String) : Array(String)
        @memory_manager.search(query)
      end

      private def build_identity_section : String
        now = Time.local

        if @lite_mode
          # Lite identity for token-constrained providers
          <<-TEXT
          # Identity

          You are a helpful AI assistant running as part of Crybot.

          **Current Time:** #{now.to_s("%Y-%m-%d %H:%M:%S %Z")}
          TEXT
        else
          # Full identity with tool documentation
          memory_stats = @memory_manager.stats

          <<-TEXT
          # Identity

          You are a helpful AI assistant. Your users may call you by various names - that's fine.
          You are running as part of Crybot, a Crystal-based personal AI system.

          **Current Time:** #{now.to_s("%Y-%m-%d %H:%M:%S %Z")}

          **Workspace Paths:**
          - Config: #{Config::Loader.config_dir}
          - Workspace: #{@workspace_dir}
          - Sessions: #{Config::Loader.sessions_dir}
          - Memory: #{Config::Loader.memory_dir}
          - Skills: #{Config::Loader.skills_dir}

          **Model:** #{@config.agents.defaults.model}
          **Max Tool Iterations:** #{@config.agents.defaults.max_tool_iterations}

          **Memory Status:**
          - Main memory: #{memory_stats["memory_file_size"]} bytes
          - Log entries: #{memory_stats["log_file_count"]}
          - Log size: #{memory_stats["log_total_size"]} bytes

          **Memory Tools Available:**
          - `save_memory(content)` - Save important facts, preferences, or information to long-term memory (MEMORY.md)
          - `search_memory(query)` - Search long-term memory and daily logs for information
          - `list_recent_memories(days)` - List recent memory entries from daily logs
          - `record_memory(content)` - Record events, actions, or observations to the daily log
          - `memory_stats()` - Get memory usage statistics

          **File & System Tools Available:**
          - `exec(command, timeout)` - Execute shell commands (IMPORTANT: Use this for running any terminal commands)
          - `read_file(path)` - Read file contents
          - `write_file(path, content)` - Write/create files
          - `edit_file(path, old_content, new_content, count)` - Edit existing files
          - `list_dir(path)` - List directory contents

          **Web Tools Available:**
          - `web_search(query, max_results)` - Search the web
          - `web_fetch(url)` - Fetch and read web pages

          **MCP (Model Context Protocol) Tools:**
          - You have access to various MCP servers that provide additional tools
          - MCP tools appear with names like `server_name/tool_name` (e.g., `playwright/browser_navigate`)
          - **IMPORTANT: MCP servers are SHARED resources with locking**
          - When you use an MCP tool, you acquire an exclusive lock on that server
          - Other agents must wait until you're done
          - **MCP state is NOT preserved between your tool calls**
          - Always assume each sequence starts fresh - navigate before clicking, re-query before acting
          - Example: For Playwright, always do navigate → click, never assume page is still loaded
          - Keep your MCP operations concise and complete them in as few tool calls as possible

          **CRITICAL: How to Use Tools:**
          When you need to use a tool, you MUST call it using function calling syntax. Do NOT just write code blocks or explain what you would do.
          - **WRONG**: "Here's the command to run: ```bash ping 8.8.8.8 ```"
          - **RIGHT**: Call the `exec` tool with arguments `{"command": "ping -c 4 8.8.8.8"}`

          **Available tools will be provided in the tools array. You MUST call them directly - don't just show code!**

          **When to use tools:**
          - Use `exec()` for ANY shell command or terminal operation (git, build tools, file operations, etc.)
          - Use `write_file()` + `exec()` to create and run scripts
          - Use `read_file()` to examine code, configs, and documentation
          - Use `web_search()` and `web_fetch()` for current information
          - Use `save_memory()` for facts worth remembering indefinitely (user preferences, important decisions, project details)
          - Use `record_memory()` for session tracking (what you did, tasks completed, conversations)
          - Use `search_memory()` when you need to recall previous information
          - Use `list_recent_memories()` to review recent activity
          TEXT
        end
      end

      private def build_bootstrap_section : String
        sections = [] of String

        bootstrap_files = [
          {"AGENTS.md", "Agent Configuration"},
          {"SOUL.md", "Core Behavior"},
          {"USER.md", "User Preferences"},
          {"TOOLS.md", "Tool Documentation"},
        ]

        bootstrap_files.each do |(filename, title)|
          path = @workspace_dir / filename
          if File.exists?(path)
            content = File.read(path)
            sections << "# #{title}\n\n#{content}"
          end
        end

        sections.empty? ? "" : sections.join("\n\n---\n\n")
      end

      private def build_memory_section : String
        memory = @memory_manager.read
        recent = @memory_manager.get_recent(3) # Last 3 days of logs

        parts = [] of String

        if !memory.empty?
          parts << "# Long-term Memory\n\n#{memory}"
        end

        if !recent.empty?
          parts << "# Recent Activity (Last 3 Days)\n\n" + recent.join("\n\n")
        end

        parts.empty? ? "" : parts.join("\n\n---\n\n")
      end

      private def build_skills_section : String
        # Build skills summary from loaded skills manager
        skills_summary = @skill_manager.build_summary

        # Also include legacy SKILL.md files for documentation
        skills = Skills.new(@workspace_dir)
        legacy_summary = skills.build_summary

        parts = [] of String
        parts << skills_summary unless skills_summary.empty?
        parts << legacy_summary unless legacy_summary.empty?

        parts.empty? ? "" : "# Available Skills\n\n#{parts.join("\n\n")}"
      end

      private def build_voice_instructions : String
        <<-TEXT
        # Voice Output Instructions

        Your response will be read aloud using text-to-speech. Follow these guidelines:

        **Important:**
        - DO NOT introduce yourself or say your name
        - DO NOT say things like "I'm Crybot" or "I am your assistant"
        - Just answer the user's question directly without preamble
        - Get straight to the point - no greetings, no sign-offs

        **Format for Speech:**
        - NO emojis - they don't work well in speech
        - NO markdown formatting - use plain, natural language
        - Write numbers as words (e.g., "five" instead of "5", "one thousand" instead of "1000")
        - Avoid abbreviations - spell out words instead
        - Use natural, conversational phrasing that sounds good when spoken
        - Keep sentences relatively short and easy to follow
        - Avoid bullet points and lists - use flowing paragraphs instead
        - Don't use visual formatting like "**bold**" or "`code`"
        - For code snippets, describe what the code does rather than reading it character by character
        - Avoid URLs and web addresses - describe the resource instead
        - Use contractions naturally (e.g., "don't", "can't", "you're")
        - Write dates and times in spoken format (e.g., "January fifth" instead of "1/5")

        **Example:**
        Instead of: "Here are 5 steps: 1. Download the file 2. Run `./install.sh`"
        Write: "Here are the five steps you need to follow. First, download the installation file. Then run the install script."

        Remember: Your response is being spoken, not read. Make it sound natural and conversational. NO self-introductions!
        TEXT
      end
    end
  end
end
