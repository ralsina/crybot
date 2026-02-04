require "json"
require "../../agent/skill_manager"
require "../../agent/skill_config"
require "../../config/loader"

module Crybot
  module Web
    module Handlers
      class SkillsHandler
        @skills_dir : Path
        @skill_manager : Agent::SkillManager

        def initialize(@skill_manager = Agent::SkillManager.new)
          @skills_dir = Config::Loader.skills_dir
        end

        # List all skills (loaded and unloaded)
        def list_skills(env) : String
          skills = [] of Hash(String, JSON::Any)

          # Ensure skills directory exists
          Dir.mkdir_p(@skills_dir) unless Dir.exists?(@skills_dir)

          # Scan for skill directories
          Dir.each_child(@skills_dir) do |skill_name|
            skill_dir = @skills_dir / skill_name
            next unless Dir.exists?(skill_dir)

            skill_file = skill_dir / "skill.yml"
            skill_md = skill_dir / "SKILL.md"

            skill_info = Hash(String, JSON::Any).new
            skill_info["name"] = JSON::Any.new(skill_name)
            skill_info["dir_name"] = JSON::Any.new(skill_name)

            # Check if skill.yml exists
            if File.exists?(skill_file)
              begin
                config = Agent::SkillConfig.from_file(skill_file)
                config.load_credentials_from_file(skill_dir)

                # Build config hash
                credentials_array = config.credentials.try do |creds|
                  creds.map { |c| JSON::Any.new(c.to_h) }
                end || [] of JSON::Any

                config_hash = {
                  "name"             => JSON::Any.new(config.name),
                  "version"          => JSON::Any.new(config.version),
                  "description"      => JSON::Any.new(config.description),
                  "tool_name"        => JSON::Any.new(config.tool.name),
                  "tool_description" => JSON::Any.new(config.tool.description),
                  "credentials"      => JSON::Any.new(credentials_array),
                }
                skill_info["config"] = JSON::Any.new(config_hash)
                skill_info["has_config"] = JSON::Any.new(true)
                skill_info["config_valid"] = JSON::Any.new(true)
                skill_info["config_error"] = JSON::Any.new(nil)

                # Check if loaded
                is_loaded = @skill_manager.has?(skill_name)
                skill_info["loaded"] = JSON::Any.new(is_loaded)

                # Check credential status
                missing_creds = config.missing_credentials
                if is_loaded
                  skill = @skill_manager.get(skill_name)
                  if skill
                    missing_creds = skill.missing_credentials
                  end
                end

                missing_creds_array = missing_creds.map { |c| JSON::Any.new(c.to_h) }
                skill_info["missing_credentials"] = JSON::Any.new(missing_creds_array)
                skill_info["cred_status"] = JSON::Any.new(if missing_creds.empty?
                  "ok"
                else
                  "missing"
                end)
              rescue e : Exception
                skill_info["has_config"] = JSON::Any.new(true)
                skill_info["config_valid"] = JSON::Any.new(false)
                skill_info["config_error"] = JSON::Any.new(e.message || "Unknown error")
                skill_info["loaded"] = JSON::Any.new(false)
                skill_info["cred_status"] = JSON::Any.new("unknown")
                skill_info["missing_credentials"] = JSON::Any.new([] of JSON::Any)
              end
            else
              skill_info["has_config"] = JSON::Any.new(false)
              skill_info["config_valid"] = JSON::Any.new(false)
              skill_info["loaded"] = JSON::Any.new(false)
              skill_info["cred_status"] = JSON::Any.new("unknown")
              skill_info["missing_credentials"] = JSON::Any.new([] of JSON::Any)
            end

            # Check for SKILL.md
            skill_info["has_docs"] = JSON::Any.new(File.exists?(skill_md))
            if File.exists?(skill_md)
              begin
                content = File.read(skill_md)
                skill_info["docs"] = JSON::Any.new(content)
              rescue
                skill_info["docs"] = JSON::Any.new(nil)
              end
            else
              skill_info["docs"] = JSON::Any.new(nil)
            end

            skills << skill_info
          end

          {
            skills:     skills,
            skills_dir: @skills_dir.to_s,
          }.to_json
        end

        # Get a single skill's configuration
        def get_skill(env) : String
          skill_name = env.params.url["skill"]
          skill_dir = @skills_dir / skill_name

          return not_found(env, "Skill not found") unless Dir.exists?(skill_dir)

          skill_file = skill_dir / "skill.yml"

          begin
            # Read the raw YAML content first, before parsing
            content = File.read(skill_file)

            # Try to parse the config
            config = Agent::SkillConfig.from_file(skill_file)
            config.load_credentials_from_file(skill_dir)

            # Build config hash
            credentials_array = config.credentials.try do |creds|
              creds.map { |c| JSON::Any.new(c.to_h) }
            end || [] of JSON::Any
            config_hash = {
              "name"             => JSON::Any.new(config.name),
              "version"          => JSON::Any.new(config.version),
              "description"      => JSON::Any.new(config.description),
              "tool_name"        => JSON::Any.new(config.tool.name),
              "tool_description" => JSON::Any.new(config.tool.description),
              "credentials"      => JSON::Any.new(credentials_array),
            }

            {
              name:        skill_name,
              config:      config_hash,
              config_yaml: content,
              has_docs:    File.exists?(skill_dir / "SKILL.md"),
              docs:        File.exists?(skill_dir / "SKILL.md") ? File.read(skill_dir / "SKILL.md") : nil,
            }.to_json
          rescue e : Exception
            # Even if parsing fails, try to return the raw content
            content = File.read(skill_file) rescue ""

            {
              name:        skill_name,
              config:      nil,
              config_yaml: content,
              has_docs:    File.exists?(skill_dir / "SKILL.md"),
              docs:        File.exists?(skill_dir / "SKILL.md") ? File.read(skill_dir / "SKILL.md") : nil,
              error:       "Failed to parse skill config: #{e.message}",
            }.to_json
          end
        end

        # Create or update a skill
        def save_skill(env) : String
          skill_name = env.params.url["skill"]?

          # Parse request body
          begin
            body = env.request.body.try(&.gets_to_end) || ""
            data = Hash(String, JSON::Any).from_json(body)

            # Get or determine skill name
            skill_name = data["name"]?.try(&.as_s) || skill_name
            if skill_name.nil? || skill_name.empty?
              return error_response("Skill name is required")
            end

            skill_dir = @skills_dir / skill_name
            skill_file = skill_dir / "skill.yml"

            # Get config YAML
            config_yaml = data["config"]?.try(&.as_s)
            if config_yaml.nil? || config_yaml.empty?
              return error_response("Configuration is required")
            end

            # Validate YAML structure
            begin
              config = Agent::SkillConfig.from_yaml(config_yaml)
              config.validate
            rescue e : Exception
              return error_response("Invalid YAML: #{e.message}")
            end

            # Create directory if needed
            Dir.mkdir_p(skill_dir) unless Dir.exists?(skill_dir)

            # Save credentials if provided
            if creds_data = data["credentials"]?.try(&.as_h?)
              creds_data.each do |key, value|
                config.set_credential(key, value.as_s)
              end
              config.save_credentials_to_file(skill_dir)
            end

            # Write skill.yml
            File.write(skill_file, config_yaml)

            # Optionally write SKILL.md
            if docs = data["docs"]?.try(&.as_s)
              skill_md = skill_dir / "SKILL.md"
              File.write(skill_md, docs)
            end

            {
              success:       true,
              message:       "Skill saved successfully",
              name:          skill_name,
              reload_needed: true,
            }.to_json
          rescue e : Exception
            error_response("Failed to save skill: #{e.message}")
          end
        end

        # Delete a skill
        def delete_skill(env) : String
          skill_name = env.params.url["skill"]
          skill_dir = @skills_dir / skill_name

          return not_found(env, "Skill not found") unless Dir.exists?(skill_dir)

          begin
            # Remove the skill directory
            FileUtils.rm_rf(skill_dir)

            {
              success: true,
              message: "Skill deleted successfully",
              name:    skill_name,
            }.to_json
          rescue e : Exception
            error_response("Failed to delete skill: #{e.message}")
          end
        end

        # Reload all skills
        def reload_skills(env) : String
          # Force reload by creating new manager
          new_manager = Agent::SkillManager.new
          results = new_manager.load_all

          loaded_count = results.count { |r| r[:status] == "loaded" }
          missing_count = results.count { |r| r[:status] == "missing_credentials" }
          error_count = results.count { |r| r[:status] == "error" }

          {
            success: true,
            message: "Skills reloaded",
            loaded:  loaded_count,
            missing: missing_count,
            errors:  error_count,
            results: results.map do |r|
              {
                name:   r[:name],
                status: r[:status],
                error:  r[:error],
              }
            end,
          }.to_json
        end

        # Set credentials for a skill
        def set_credentials(env) : String
          body = env.request.body.try(&.gets_to_end) || ""
          data = Hash(String, JSON::Any).from_json(body)

          skill_name = data["skill"]?.try(&.as_s)
          if skill_name.nil? || skill_name.empty?
            return error_response("skill is required")
          end

          skill_dir = @skills_dir / skill_name
          skill_file = skill_dir / "skill.yml"

          return error_response("Skill not found") unless File.exists?(skill_file)

          # Load existing config
          config = Agent::SkillConfig.from_file(skill_file)
          config.load_credentials_from_file(skill_dir)

          # Set credentials
          creds_data = data["credentials"]?.try(&.as_h?)
          if creds_data.nil?
            return error_response("credentials is required")
          end

          creds_data.each do |key, value|
            config.set_credential(key, value.as_s)
          end

          # Save to credentials file
          config.save_credentials_to_file(skill_dir)

          {
            success: true,
            message: "Credentials saved successfully",
            skill:   skill_name,
          }.to_json
        rescue e : Exception
          error_response("Failed to set credentials: #{e.message}")
        end

        private def error_response(message : String) : String
          {
            error: message,
          }.to_json
        end

        private def not_found(env, message : String) : String
          env.response.status_code = 404
          {
            error: message,
          }.to_json
        end
      end
    end
  end
end
