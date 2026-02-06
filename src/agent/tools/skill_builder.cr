require "../tools/base"
require "../../config/loader"
require "../skill_config"
require "file_utils"

module Crybot
  module Agent
    module Tools
      # Tool for creating new skills by exploring commands
      class CreateSkillTool < Tool
        def name : String
          "create_skill"
        end

        def description : String
          "Creates a new skill by exploring a command and generating appropriate configuration. Use this when the user asks to learn about a command they have installed."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "command" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("The command name to explore and create a skill for (e.g., 'tldr', 'grep', 'find')"),
              }),
              "name" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("Optional skill name (defaults to command name)"),
              }),
              "description" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("Optional description of what the skill does"),
              }),
            }),
            "required" => JSON::Any.new([JSON::Any.new("command")] of JSON::Any),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          command = args["command"]?.try(&.as_s) || ""
          skill_name = args["name"]?.try(&.as_s) || command
          description = args["description"]?.try(&.as_s) || ""

          if command.empty?
            return "Error: 'command' parameter is required"
          end

          # Check if command exists
          unless command_exists?(command)
            return "Error: Command '#{command}' not found. Please make sure it's installed and in your PATH."
          end

          # Explore the command
          info = explore_command(command)

          # Generate skill name from command if not provided
          if skill_name.empty?
            skill_name = command
          end

          # Sanitize skill name
          skill_name = skill_name.downcase.gsub(/[^a-z0-9_\-]/, "_")

          # Create skill directory
          skills_dir = Config::Loader.skills_dir
          Dir.mkdir_p(skills_dir) unless Dir.exists?(skills_dir)

          skill_dir = skills_dir / skill_name

          if Dir.exists?(skill_dir)
            return "Error: Skill '#{skill_name}' already exists. Please choose a different name or delete the existing skill first."
          end

          Dir.mkdir(skill_dir)

          # Generate skill description if not provided
          if description.empty?
            description = info[:description] || "Run the #{command} command"
          end

          # Generate skill.yml
          tool_name = "#{command}_command"
          generate_skill_yml(skill_dir, skill_name, tool_name, description, command, info)

          # Generate SKILL.md
          generate_skill_md(skill_dir, skill_name, description, command, info)

          # Generate a simple Crystal wrapper script
          generate_wrapper_script(skill_dir, command)

          "Successfully created skill '#{skill_name}'!\n\n" \
          "Skill location: #{skill_dir}\n" \
          "Tool name: #{tool_name}\n\n" \
          "The skill has been configured with command execution type.\n" \
          "Please:\n" \
          "1. Review the generated skill.yml in the web UI (Skills section)\n" \
          "2. Click 'Reload Skills' to load the new skill\n" \
          "3. Ask me to use the #{tool_name} tool!\n\n" \
          "Skill description: #{description}"
        rescue e : Exception
          "Error creating skill: #{e.message}"
        end

        private def command_exists?(command : String) : Bool
          Process.new("which", [command]).wait.success?
        rescue
          false
        end

        private def explore_command(command : String) : NamedTuple(description: String?, usage: String?, examples: Array(String))
          description = nil
          usage = nil
          examples = [] of String

          # Try tldr first (most concise and practical)
          tldr_output = run_command("tldr", [command])
          unless tldr_output.empty?
            description, usage, examples = parse_tldr(tldr_output)
          end

          # Try --help if tldr didn't work
          if description.nil?
            help_output = run_command(command, ["--help"])
            if help_output.empty?
              help_output = run_command(command, ["-h"])
            end
            unless help_output.empty?
              description, usage, examples = parse_help_output(help_output, command)
            end
          end

          # Fallback to basic info
          description ||= "Run the #{command} command"
          usage ||= "#{command} [options] [arguments]"

          {description: description, usage: usage, examples: examples}
        end

        private def run_command(cmd : String, args : Array(String) = [] of String) : String
          output = IO::Memory.new
          error = IO::Memory.new

          process = Process.new(cmd, args,
            output: output,
            error: error
          )

          status = process.wait

          result = output.to_s.strip

          # Only return output if command succeeded
          status.success? ? result : ""
        rescue
          ""
        end

        private def parse_tldr(output : String) : Tuple(String?, String?, Array(String))
          lines = output.split('\n')
          description = nil
          usage = nil
          examples = [] of String

          current_section = nil
          buffer = [] of String

          lines.each do |line|
            line = line.strip

            # Skip empty lines and metadata
            next if line.empty?
            next if line.starts_with?('#')

            # Section headers
            if line.starts_with?('-')
              current_section = line
              next
            end

            case current_section
            when /description/i
              description ||= line
            when nil
              # First line before any section might be description
              if description.nil?
                description = line
              end
            else
              # Examples and usage
              if line.includes?('-')
                examples << line
              else
                buffer << line
              end
            end
          end

          usage = buffer.join(" ") if buffer.any?

          {description, usage, examples}
        end

        private def parse_help_output(output : String, command : String) : Tuple(String?, String?, Array(String))
          lines = output.split('\n')

          # Try to find description (first non-empty line that's not usage/help header)
          description = nil
          usage = nil
          examples = [] of String
          in_examples = false

          lines.each do |line|
            line = line.strip

            # Look for description
            if description.nil? && !line.empty? && !line.starts_with?("-") && !line.starts_with?("Usage")
              description = line[0..100] # Truncate long descriptions
            end

            # Look for usage
            if line.starts_with?("Usage") || line.starts_with?("SYNOPSIS")
              parts = line.split(':', 2)
              if parts.size == 2
                usage = parts[1].strip
              end
            end

            # Look for examples section
            if line.downcase.includes?("example")
              in_examples = true
            elsif in_examples && line.starts_with?("-")
              examples << line
            elsif in_examples && line.empty?
              in_examples = false
            end
          end

          usage ||= "#{command} [options]"
          description ||= "Run the #{command} command"

          {description, usage, examples}
        end

        private def generate_skill_yml(dir : Path, name : String, tool_name : String, description : String, command : String, info : NamedTuple) : Nil
          # Build parameters based on what we discovered
          properties = {} of String => JSON::Any
          required = [] of String

          # Add common parameters that many commands accept
          properties["args"] = JSON::Any.new({
            "type"        => JSON::Any.new("string"),
            "description" => JSON::Any.new("Arguments to pass to the command"),
          })
          required << "args"

          properties["options"] = JSON::Any.new({
            "type"        => JSON::Any.new("string"),
            "description" => JSON::Any.new("Command options/flags (e.g., '-v', '--help')"),
          })

          yaml_params = build_yaml_params(properties, required)
          required_yaml = required.map { |r| "      - \"#{r}\"" }.join("\n")

          skill_yml = <<-YAML
name: #{name}
version: 1.0.0
description: #{description}

tool:
  name: #{tool_name}
  description: Execute the #{command} command
  parameters:
    type: object
    properties:#{yaml_params}
    required:
#{required_yaml}

execution:
  type: command
  command:
    command: #{command}
    args:
      - "'{{options}}'"
      - "'{{args}}'"
    working_dir: null
YAML

          File.write(dir / "skill.yml", skill_yml)

          # Validate the generated YAML
          unless validate_yaml(skill_yml, dir / "skill.yml")
            raise "Generated YAML is invalid. Please check the logs."
          end
        end

        private def build_yaml_params(properties : Hash(String, JSON::Any), required : Array(String)) : String
          return "" if properties.empty?

          lines = [] of String
          properties.each do |key, prop|
            prop_h = prop.as_h
            lines << "    #{key}:"
            lines << "      type: #{prop_h["type"].as_s}"
            if desc = prop_h["description"]?
              lines << "      description: #{desc.as_s}"
            end
          end
          lines.join("\n")
        end

        private def validate_yaml(yaml_content : String, file_path : Path) : Bool
          begin
            # Try to parse the YAML to validate it
            skill_config = SkillConfig.from_yaml(yaml_content)
            skill_config.validate
            true
          rescue e : Exception
            puts "[SkillBuilder] YAML validation failed for #{file_path}: #{e.message}"
            puts "[SkillBuilder] Generated YAML:\n#{yaml_content}"
            false
          end
        end

        private def generate_skill_md(dir : Path, name : String, description : String, command : String, info : NamedTuple) : Nil
          examples = info[:examples]
          example_text = examples.empty? ? "" : "\n## Examples\n\n" + examples.map { |e| "- `#{e}`" }.join("\n") + "\n"

          skill_md = <<-MD
# #{name.capitalize} Skill

#{description}

## Usage

This skill provides the `#{command}_command` tool to execute the #{command} command.

## Common Options

```
#{info[:usage] || "#{command} [options] [arguments]"}
```
#{example_text}
## Notes

- The skill executes the #{command} command directly on your system
- Make sure #{command} is installed and available in your PATH
- Use the web UI to review and customize the skill configuration
MD

          File.write(dir / "SKILL.md", skill_md)
        end

        private def generate_wrapper_script(dir : Path, command : String) : Nil
          # Note: We're not actually creating a Crystal wrapper anymore
          # The skill.yml uses command execution which is simpler
          # But we could add additional helper files here if needed
        end
      end
    end
  end
end
