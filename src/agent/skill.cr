require "http/client"
require "json"
require "./skill_config"
require "./template_engine"
require "./response_parser"
require "../mcp/manager"

module Crybot
  module Agent
    # Represents a loaded skill that can be executed
    class Skill
      getter config : SkillConfig
      property skill_dir : Path
      property mcp_manager : MCP::Manager?

      def initialize(@config : SkillConfig, @skill_dir : Path, @mcp_manager : MCP::Manager? = nil)
      end

      # Execute the skill with given arguments
      def execute(args : Hash(String, JSON::Any)) : String
        case @config.execution.type
        when "http"
          execute_http(args)
        when "command"
          execute_command(args)
        when "mcp"
          execute_mcp(args)
        else
          "Error: Unknown execution type: #{@config.execution.type}"
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def execute_http(args : Hash(String, JSON::Any)) : String
        http_config = @config.execution.http_exec

        begin
          # Build URL with template substitution (including credentials)
          url = TemplateEngine.render(http_config.url, args, @config.credential_values)

          # Build query params
          query_params = build_query_params(http_config, args)

          # Build headers
          headers = build_headers(http_config, args)

          # Make the HTTP request
          response = case http_config.method.upcase
                     when "GET"
                       if query_params.empty?
                         HTTP::Client.get(url, headers: headers)
                       else
                         # Add query string to URL
                         query_string = HTTP::Params.encode(query_params)
                         full_url = url.includes?('?') ? "#{url}&#{query_string}" : "#{url}?#{query_string}"
                         HTTP::Client.get(full_url, headers: headers)
                       end
                     when "POST"
                       body = http_config.body
                       body_content = body ? TemplateEngine.render(body, args, @config.credential_values) : ""
                       HTTP::Client.post(url, body: body_content, headers: headers)
                     when "PUT"
                       body = http_config.body
                       body_content = body ? TemplateEngine.render(body, args, @config.credential_values) : ""
                       HTTP::Client.put(url, body: body_content, headers: headers)
                     when "DELETE"
                       HTTP::Client.delete(url, headers: headers)
                     when "PATCH"
                       body = http_config.body
                       body_content = body ? TemplateEngine.render(body, args, @config.credential_values) : ""
                       HTTP::Client.patch(url, body: body_content, headers: headers)
                     else
                       return "Error: Unsupported HTTP method: #{http_config.method}"
                     end

          # Parse and format the response
          if response.success?
            response_body = response.body

            # Apply response format template if provided
            format_template = http_config.response_format
            if format_template && !format_template.empty?
              ResponseParser.parse(response_body, format_template)
            else
              # Return pretty-printed JSON if it's JSON, otherwise raw response
              begin
                parsed = JSON.parse(response_body)
                parsed.to_pretty_json
              rescue JSON::ParseException
                response_body
              end
            end
          else
            "Error: HTTP #{response.status_code} - #{response.status_message}: #{response.body}"
          end
        rescue e : URI::Error
          "Error: Invalid URL: #{e.message}"
        rescue e : IO::Error
          "Error: HTTP request failed: #{e.message}"
        rescue e : Exception
          "Error: #{e.class.name} - #{e.message}"
        end
      end

      private def build_query_params(http_config : HTTPExecutionConfig, args : Hash(String, JSON::Any)) : Hash(String, String)
        result = {} of String => String

        # Add params from config with template substitution
        http_config.params.try do |params|
          params.each do |key, template|
            result[key] = TemplateEngine.render(template, args, @config.credential_values)
          end
        end

        result
      end

      private def build_headers(http_config : HTTPExecutionConfig, args : Hash(String, JSON::Any)) : HTTP::Headers
        result = HTTP::Headers.new

        # Default headers
        result["User-Agent"] = "Crybot/1.0"

        # Add headers from config with template substitution
        http_config.headers.try do |headers|
          headers.each do |key, template|
            result.add(key, TemplateEngine.render(template, args, @config.credential_values))
          end
        end

        result
      end

      private def execute_command(args : Hash(String, JSON::Any)) : String
        command_config = @config.execution.command_exec

        begin
          # Build the command
          cmd = command_config.command

          # Build args with template substitution
          cmd_args = command_config.args || [] of String

          # Render each arg through template engine
          rendered_args = cmd_args.map do |arg_template|
            TemplateEngine.render(arg_template, args, @config.credential_values)
          end

          # Build full command array
          full_command = [cmd] + rendered_args

          # Set working directory if specified
          working_dir = command_config.working_dir
          if working_dir && !working_dir.empty? && working_dir != "null"
            Dir.cd(working_dir) do
              run_command(full_command)
            end
          else
            run_command(full_command)
          end
        rescue e : Exception
          "Error executing command: #{e.message}"
        end
      end

      private def run_command(argv : Array(String)) : String
        output = IO::Memory.new
        error = IO::Memory.new

        begin
          process = Process.new(
            argv[0],
            argv[1..-1],
            output: output,
            error: error
          )

          status = process.wait

          output_str = output.to_s.strip
          error_str = error.to_s.strip

          if status.success?
            output_str.empty? ? error_str : output_str
          else
            "Error: Command failed with exit code #{status.exit_code}\n#{error_str}"
          end
        rescue e : Exception
          "Error: Failed to run command: #{e.message}"
        end
      end

      private def execute_mcp(args : Hash(String, JSON::Any)) : String
        mcp_config = @config.execution.mcp_exec

        manager = @mcp_manager
        return "Error: MCP manager not available. Make sure MCP is configured in config.yml" unless manager

        begin
          # Build the tool name: server/tool
          tool_name = "#{mcp_config.server}/#{mcp_config.tool}"

          # Map arguments using the args_mapping or pass through directly
          mcp_args = build_mcp_args(args, mcp_config)

          # Find and execute the MCP tool
          # We need to look it up in the registry since MCP tools are registered there
          tool = Tools::Registry.get(tool_name)
          return "Error: MCP tool '#{tool_name}' not found. Make sure the MCP server is configured and running" unless tool

          tool.execute(mcp_args)
        rescue e : Exception
          "Error executing MCP tool: #{e.message}"
        end
      end

      private def build_mcp_args(skill_args : Hash(String, JSON::Any), mcp_config : MCPExecutionConfig) : Hash(String, JSON::Any)
        if mapping = mcp_config.args_mapping
          # Use the mapping to transform skill arguments to MCP arguments
          result = {} of String => JSON::Any

          mapping.each do |mcp_key, skill_key_template|
            # Render the template (could be a direct reference or a template)
            value = TemplateEngine.render(skill_key_template, skill_args, @config.credential_values)
            result[mcp_key] = JSON::Any.new(value)
          end

          # Also include any args not in the mapping
          skill_args.each do |key, value|
            unless mapping.values.any? { |v| v == key || v.includes?("${#{key}}") || v.includes?("{{#{key}}}") }
              result[key] = value
            end
          end

          result
        else
          # No mapping, pass through all arguments directly
          skill_args
        end
      end

      # Get the tool name for this skill
      def tool_name : String
        @config.tool.name
      end

      # Get the tool description for this skill
      def tool_description : String
        @config.tool.description
      end

      # Get the tool parameters for this skill
      def tool_parameters : Hash(String, JSON::Any)
        @config.tool.parameters.to_h
      end

      # Get missing credentials for display
      def missing_credentials : Array(CredentialRequirement)
        @config.missing_credentials
      end

      # Check if this skill has credential requirements
      def has_credentials? : Bool
        !@config.credentials.nil? && !@config.credentials.empty?
      end

      # Get all credential definitions
      def credentials : Array(CredentialRequirement)
        @config.credentials || [] of CredentialRequirement
      end
    end
  end
end
