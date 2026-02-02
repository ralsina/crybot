require "time"
require "../config/loader"
require "../providers/base"
require "./memory"
require "./skills"
require "./tools/registry"

module Crybot
  module Agent
    class ContextBuilder
      @config : Config::ConfigFile
      @workspace_dir : Path
      @memory_manager : MemoryManager

      def initialize(@config : Config::ConfigFile)
        @workspace_dir = Config::Loader.workspace_dir
        @memory_manager = MemoryManager.new(@workspace_dir)
      end

      def build_system_prompt : String
        parts = [] of String

        # Identity section
        parts << build_identity_section

        # Bootstrap files
        parts << build_bootstrap_section

        # Memory
        parts << build_memory_section

        # Skills
        parts << build_skills_section

        parts.compact.join("\n\n")
      end

      def build_messages(user_message : String, history : Array(Providers::Message)) : Array(Providers::Message)
        messages = [] of Providers::Message

        # System prompt
        system_content = build_system_prompt
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
        memory_stats = @memory_manager.stats

        <<-TEXT
        # Identity

        You are Crybot, a personal AI assistant built in Crystal.

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

        **When to use memory:**
        - Use `save_memory()` for facts worth remembering indefinitely (user preferences, important decisions, project details)
        - Use `record_memory()` for session tracking (what you did, tasks completed, conversations)
        - Use `search_memory()` when you need to recall previous information
        - Use `list_recent_memories()` to review recent activity
        TEXT
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
        skills = Skills.new(@workspace_dir)
        summary = skills.build_summary

        summary.empty? ? "" : "# Available Skills\n\n#{summary}"
      end
    end
  end
end
