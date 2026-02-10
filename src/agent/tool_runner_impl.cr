require "./tools/registry"
require "./tools/shell"
require "./tools/filesystem"
require "./tools/memory"
require "./tools/web"
require "./tools/skill_builder"
require "./tools/web_scraper_skill"
require "../landlock_wrapper"
require "json"

# Make sure the Tools::Registry is accessible
include Crybot::Agent

# Tool Runner Implementation - Landlocked subprocess for executing a single tool call
#
# Called via: crybot tool-runner <tool_name> <json_args>
#
# Exit codes:
#  0 - Success, tool result on stdout
#  1 - Tool execution error
#  42 - Landlock access denied, path written to stderr
#  43 - Invalid arguments

module Crybot
  module ToolRunnerImpl
    # Special exit code for Landlock access denial
    EXIT_ACCESS_DENIED = 42

    def self.run(tool_name : String, args_json : String) : Nil
      # Register all built-in tools for this subprocess
      register_built_in_tools

      # Parse arguments
      args = begin
        JSON.parse(args_json).as_h
      rescue
        STDERR.puts "Error: Invalid JSON arguments"
        exit 43
      end

      # Convert JSON::Any hash to String -> JSON::Any for registry
      args_hash = args.transform_values { |v| v }

      # Apply Landlock sandbox before executing tool
      LandlockWrapper.ensure_sandbox([] of String)

      # Execute the tool
      result = Tools::Registry.execute(tool_name, args_hash)

      # Check if result contains permission denied (Landlock block)
      if LandlockWrapper.landlock_error?(result)
        # Extract path from error message
        path = extract_path_from_error(result)

        if path
          # Write path to stderr so monitor can pick it up
          STDERR.puts "LANDLOCK_DENIED:#{path}"
          exit EXIT_ACCESS_DENIED
        end
      end

      # Output result
      puts result
      exit 0
    rescue e : Exception
      # Log the error for debugging
      STDERR.puts "[ToolRunner] Error executing #{tool_name}: #{e.message}"
      STDERR.puts e.backtrace.join("\n") if ENV["DEBUG"]?

      # Check if this is a Landlock access denial
      if LandlockWrapper.landlock_error?(e.message || "")
        # Extract path from error message if possible
        error_msg = e.message || ""
        path = extract_path_from_error(error_msg)

        if path
          # Write path to stderr so monitor can pick it up
          STDERR.puts "LANDLOCK_DENIED:#{path}"
          exit EXIT_ACCESS_DENIED
        end
      end

      # Regular error
      STDERR.puts "Error: #{e.message}"
      exit 1
    end

    # Register all built-in tools
    private def self.register_built_in_tools : Nil
      Tools::Registry.register(Tools::ExecTool.new)
      Tools::Registry.register(Tools::ReadFileTool.new)
      Tools::Registry.register(Tools::WriteFileTool.new)
      Tools::Registry.register(Tools::EditFileTool.new)
      Tools::Registry.register(Tools::ListDirTool.new)
      Tools::Registry.register(Tools::SaveMemoryTool.new)
      Tools::Registry.register(Tools::SearchMemoryTool.new)
      Tools::Registry.register(Tools::ListRecentMemoriesTool.new)
      Tools::Registry.register(Tools::RecordMemoryTool.new)
      Tools::Registry.register(Tools::MemoryStatsTool.new)
      Tools::Registry.register(Tools::WebSearchTool.new)
      Tools::Registry.register(Tools::WebFetchTool.new)
      Tools::Registry.register(Tools::CreateSkillTool.new)
      Tools::Registry.register(Tools::CreateWebScraperSkillTool.new)
    end

    # Extract file path from permission denied error
    private def self.extract_path_from_error(error_msg : String) : String?
      # Common patterns:
      # "sh: line 1: /path/to/file: Permission denied"
      # "tee: /path/to/file: Permission denied"
      # "'/path/to/file': Permission denied" (with quotes)
      # "/path/to/file: Permission denied"

      match = error_msg.match(/(?:sh:|tee:|echo:)?\s*line\s*\d+:\s*['"]?([^\s'"]+)['"]?:\s*Permission\s+denied/i)
      if match
        return match[1]
      end

      # Try another pattern (simpler)
      match = error_msg.match(/['"]?([^\s'"]+)['"]?:\s*Permission\s+denied/i)
      if match
        return match[1]
      end

      nil
    end
  end
end
