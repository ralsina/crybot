require "yaml"

module Crybot
  module Agent
    # HTTP execution configuration
    struct HTTPExecutionConfig
      include YAML::Serializable

      property url : String
      property method : String = "GET"
      property params : Hash(String, String)?
      property headers : Hash(String, String)?
      property body : String?
      property response_format : String?

      def validate : Nil
        raise "HTTP execution requires 'url'" if @url.empty?
      end
    end

    # Command execution configuration
    struct CommandExecutionConfig
      include YAML::Serializable

      property command : String
      property args : Array(String)?
      property working_dir : String?

      def validate : Nil
        raise "Command execution requires 'command'" if @command.empty?
      end
    end

    # MCP execution configuration - calls MCP tools directly
    struct MCPExecutionConfig
      include YAML::Serializable

      property server : String
      property tool : String
      property args_mapping : Hash(String, String)?

      def validate : Nil
        raise "MCP execution requires 'server'" if @server.empty?
        raise "MCP execution requires 'tool'" if @tool.empty?
      end
    end

    # Execution configuration base class
    class ExecutionConfig
      include YAML::Serializable

      property type : String
      property http : HTTPExecutionConfig?
      property command : CommandExecutionConfig?
      property mcp : MCPExecutionConfig?

      def validate : Nil
        case @type
        when "http"
          if http_config = @http
            http_config.validate
          else
            raise "HTTP execution config not found"
          end
        when "command"
          if command_config = @command
            command_config.validate
          else
            raise "Command execution config not found"
          end
        when "mcp"
          if mcp_config = @mcp
            mcp_config.validate
          else
            raise "MCP execution config not found"
          end
        else
          raise "Unknown execution type: #{@type}"
        end
      end

      def http_exec : HTTPExecutionConfig
        @http || raise "Not an HTTP execution config"
      end

      def command_exec : CommandExecutionConfig
        @command || raise "Not a command execution config"
      end

      def mcp_exec : MCPExecutionConfig
        @mcp || raise "Not an MCP execution config"
      end
    end

    # Credential requirement for a skill
    struct CredentialRequirement
      include YAML::Serializable

      property name : String        # e.g., "api_key"
      property description : String # e.g., "OpenWeatherMap API Key"
      property required : Bool = true
      property placeholder : String? # e.g., "your_api_key_here"

      def to_h : Hash(String, JSON::Any)
        hash = {} of String => JSON::Any
        hash["name"] = JSON::Any.new(@name)
        hash["description"] = JSON::Any.new(@description)
        hash["required"] = JSON::Any.new(@required)
        if placeholder = @placeholder
          hash["placeholder"] = JSON::Any.new(placeholder)
        end
        hash
      end
    end

    # Tool property definition for YAML
    struct ToolPropertyConfig
      include YAML::Serializable

      property type : String
      property description : String?
      property enum_values : Array(String)?
      property default : String?

      def to_json_any : JSON::Any
        prop_hash = {} of String => JSON::Any
        prop_hash["type"] = JSON::Any.new(@type)

        if desc = @description
          prop_hash["description"] = JSON::Any.new(desc)
        end

        if enum_vals = @enum_values
          enum_array = enum_vals.map { |e| JSON::Any.new(e) }
          prop_hash["enum"] = JSON::Any.new(enum_array)
        end

        if default = @default
          prop_hash["default"] = JSON::Any.new(default)
        end

        JSON::Any.new(prop_hash)
      end
    end

    # Tool parameters schema
    struct ToolParameters
      include YAML::Serializable

      property type : String = "object"
      property properties : Hash(String, ToolPropertyConfig) = {} of String => ToolPropertyConfig
      property required : Array(String) = [] of String

      def to_h : Hash(String, JSON::Any)
        props_hash = {} of String => JSON::Any
        @properties.each do |key, prop|
          props_hash[key] = prop.to_json_any
        end

        required_array = @required.map { |required| JSON::Any.new(required) }

        {
          "type"       => JSON::Any.new(@type),
          "properties" => JSON::Any.new(props_hash),
          "required"   => JSON::Any.new(required_array),
        }
      end
    end

    # Tool definition within a skill
    struct ToolDefinition
      include YAML::Serializable

      property name : String
      property description : String
      property parameters : ToolParameters

      def to_h : Hash(String, JSON::Any)
        {
          "name"        => JSON::Any.new(@name),
          "description" => JSON::Any.new(@description),
          "parameters"  => JSON::Any.new(@parameters.to_h),
        }
      end
    end

    # Skill configuration schema
    struct SkillConfig
      include YAML::Serializable

      property name : String
      property version : String = "1.0.0"
      property description : String = ""
      property tool : ToolDefinition
      property execution : ExecutionConfig
      property credentials : Array(CredentialRequirement)?
      property note : String?
      # Storage for credential values (not serialized to YAML)
      property credential_values : Hash(String, String) = {} of String => String

      def self.from_file(path : Path) : SkillConfig
        content = File.read(path)
        from_yaml(content)
      end

      def to_yaml(path : Path) : Nil
        # Serialize without credential_values
        yaml_string = to_yaml
        File.write(path, yaml_string)
      end

      def validate : Nil
        raise "Skill config requires 'name'" if @name.empty?
        @execution.validate
      end

      # Get credential value or return nil if not set
      def get_credential(name : String) : String?
        @credential_values[name]?
      end

      # Set a credential value
      def set_credential(name : String, value : String) : Nil
        @credential_values[name] = value
      end

      # Check if all required credentials are set
      def missing_credentials : Array(CredentialRequirement)
        missing = [] of CredentialRequirement

        @credentials.try do |creds|
          creds.each do |cred|
            if cred.required && @credential_values[cred.name]?.nil?
              missing << cred
            end
          end
        end

        missing
      end

      # Check if credential values need to be saved to file
      def needs_credential_save : Bool
        @credentials.try do |creds|
          return false if creds.empty?

          creds.any? do |cred|
            !@credential_values[cred.name]?.nil?
          end
        end || false
      end

      # Save credential values to a separate file
      def save_credentials_to_file(skill_dir : Path) : Nil
        return unless needs_credential_save

        creds_file = skill_dir / "credentials.yml"
        creds_hash = {} of String => String

        @credentials.try do |creds|
          creds.each do |cred|
            if value = @credential_values[cred.name]?
              creds_hash[cred.name] = value
            end
          end
        end

        if creds_hash.empty?
          File.delete(creds_file) if File.exists?(creds_file)
        else
          File.write(creds_file, creds_hash.to_yaml)
        end
      end

      # Load credential values from a separate file
      def load_credentials_from_file(skill_dir : Path) : Nil
        creds_file = skill_dir / "credentials.yml"
        return unless File.exists?(creds_file)

        begin
          content = File.read(creds_file)
          hash = YAML.parse(content).as_h?

          hash.try do |creds|
            creds.each do |key, value|
              @credential_values[key.as_s] = value.as_s
            end
          end
        rescue e : Exception
          # Silently fail if credentials file is malformed
        end
      end
    end
  end
end
