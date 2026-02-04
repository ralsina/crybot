require "file_utils"
require "./skill_config"
require "./skill"
require "../config/loader"
require "../mcp/manager"

module Crybot
  module Agent
    # Manages skill discovery, loading, and registration
    class SkillManager
      getter skills_dir : Path
      getter loaded_skills : Hash(String, Skill)
      getter mcp_manager : MCP::Manager?

      def initialize(@skills_dir : Path = Config::Loader.skills_dir, @mcp_manager : MCP::Manager? = nil)
        @loaded_skills = {} of String => Skill
      end

      # Load all skills from the skills directory
      def load_all : Array(NamedTuple(name: String, skill: Skill?, status: String, error: String?))
        results = [] of NamedTuple(name: String, skill: Skill?, status: String, error: String?)

        # Ensure skills directory exists
        return results unless Dir.exists?(@skills_dir)

        # Scan for skill directories
        Dir.each_child(@skills_dir) do |skill_name|
          skill_dir = @skills_dir / skill_name
          next unless Dir.exists?(skill_dir)

          skill_file = skill_dir / "skill.yml"
          next unless File.exists?(skill_file)

          result = load_skill(skill_name, skill_dir, skill_file)
          results << result
        end

        results
      end

      # Load a single skill from its directory
      def load_skill(name : String, dir : Path, config_file : Path) : NamedTuple(name: String, skill: Skill?, status: String, error: String?)
        # Load the skill configuration
        config = SkillConfig.from_file(config_file)
        config.validate

        # Load credentials from file
        config.load_credentials_from_file(dir)

        # Create the skill instance with MCP manager
        skill = Skill.new(config, dir, @mcp_manager)

        # Check if all required credentials are set
        missing_creds = config.missing_credentials
        if !missing_creds.empty?
          missing_names = missing_creds.map(&.name).join(", ")
          return {
            name:   name,
            skill:  nil,
            status: "missing_credentials",
            error:  "Missing required credentials: #{missing_names}",
          }
        end

        # Store the skill
        @loaded_skills[name] = skill

        {
          name:   name,
          skill:  skill,
          status: "loaded",
          error:  nil,
        }
      rescue e : YAML::ParseException
        {
          name:   name,
          skill:  nil,
          status: "error",
          error:  "YAML parsing failed: #{e.message}",
        }
      rescue e : Exception
        {
          name:   name,
          skill:  nil,
          status: "error",
          error:  e.message || "Unknown error",
        }
      end

      # Get a loaded skill by name
      def get(name : String) : Skill?
        @loaded_skills[name]?
      end

      # Get all loaded skills
      def all : Hash(String, Skill)
        @loaded_skills
      end

      # Check if a skill is loaded
      def has?(name : String) : Bool
        @loaded_skills.has_key?(name)
      end

      # Get a list of all skill names
      def skill_names : Array(String)
        @loaded_skills.keys
      end

      # Reload all skills (clears and reloads)
      def reload : Array(NamedTuple(name: String, skill: Skill?, status: String, error: String?))
        # Clear existing skills
        @loaded_skills.clear

        # Reload all
        load_all
      end

      # Build a summary of loaded skills
      def build_summary : String
        return "" if @loaded_skills.empty?

        summary_lines = [] of String

        @loaded_skills.each do |name, skill|
          tool_name = skill.tool_name
          tool_desc = skill.tool_description
          version = skill.config.version

          summary_lines << "- **#{tool_name}** (#{name} v#{version}): #{tool_desc}"
        end

        summary_lines.join("\n")
      end
    end
  end
end
