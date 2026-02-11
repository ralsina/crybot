module Crybot
  module Agent
    # Simple template engine for variable substitution
    #
    # Supported syntax:
    # - {{variable}} - Simple variable substitution from context
    # - ${credential:name} - Credential value from skill config
    # - ${ENV_VAR} - Environment variable substitution (fallback)
    # - {% if condition %}...{% endif %} - Conditional blocks (basic support)
    class TemplateEngine
      # Substitute variables in a template string
      #
      # @param template The template string with placeholders
      # @param context Hash of variables for {{variable}} substitution
      # @param credentials Optional hash of credential values for ${credential:name} substitution
      # @return The substituted string
      def self.render(template : String, context : Hash(String, JSON::Any), credentials : Hash(String, String)? = nil) : String
        result = template

        # First, handle credentials ${credential:name}
        result = substitute_credentials(result, credentials)

        # Then, handle environment variables ${ENV_VAR}
        result = substitute_env_vars(result)

        # Then, handle conditionals {% if condition %}...{% endif %}
        result = process_conditionals(result, context)

        # Finally, handle simple variables {{variable}}
        result = substitute_variables(result, context)

        result
      end

      # Substitute credentials in the form ${credential:name}
      private def self.substitute_credentials(template : String, credentials : Hash(String, String)?) : String
        return template unless credentials

        template.gsub(/\$\{credential:([a-zA-Z0-9_]+)\}/) do |_match, io|
          cred_name = io[1]
          credentials.fetch(cred_name, "")
        end
      end

      # Substitute environment variables in the form ${ENV_VAR}
      private def self.substitute_env_vars(template : String) : String
        template.gsub(/\$\{([A-Z_][A-Z0-9_]*)\}/) do |_match, io|
          env_var = io[1]
          ENV.fetch(env_var, "")
        end
      end

      # Substitute variables in the form {{variable}}
      # Supports nested access like {{user.name}}
      private def self.substitute_variables(template : String, context : Hash(String, JSON::Any)) : String
        template.gsub(/\{\{([^}]+)\}\}/) do |_match, io|
          path = io[1].strip
          resolve_path(path, context)
        end
      end

      # Resolve a dot-notation path in the context
      # e.g., "user.name" -> context["user"]["name"]
      # ameba:disable Metrics/CyclomaticComplexity
      private def self.resolve_path(path : String, context : Hash(String, JSON::Any)) : String
        parts = path.split('.')
        current = context[parts[0]]?

        return "" if current.nil?

        parts[1..].each do |part|
          case current.raw
          when Hash
            hash = current.as_h
            current = hash[part]?
            return "" if current.nil?
          when Array
            # Handle array access with numeric index
            index = part.to_i?
            if index
              arr = current.as_a
              current = arr[index]?
              return "" if current.nil?
            else
              return ""
            end
          else
            return ""
          end
        end

        # Convert the value to string
        case current.raw
        when String
          current.as_s
        when Int64, Int32
          current.as_i.to_s
        when Float64
          current.as_f.to_s
        when Bool
          current.as_bool.to_s
        when Nil
          ""
        else
          current.to_s
        end
      end

      # Process simple if/else conditionals
      # Supports: {% if variable == value %}...{% endif %}
      # And: {% if variable %}...{% endif %} (truthiness check)
      private def self.process_conditionals(template : String, context : Hash(String, JSON::Any)) : String
        # Handle {% if variable %}...{% endif %}
        result = template.gsub(/\{%\s*if\s+(\w+)\s*%\}(.*?)\{%\s*endif\s*%\}/m) do |_match, io|
          var_name = io[1].strip
          content = io[2]
          value = context[var_name]?

          if truthy?(value)
            content
          else
            ""
          end
        end

        # Handle {% if variable == value %}...{% endif %}
        result = result.gsub(/\{%\s*if\s+(\w+)\s*==\s*["']?([^"'\s}]+)["']?\s*%\}(.*?)\{%\s*endif\s*%\}/m) do |_match, io|
          var_name = io[1].strip
          expected_value = io[2].strip
          content = io[3]

          value = context[var_name]?
          actual_value = value.try(&.as_s) || ""

          if actual_value == expected_value
            content
          else
            ""
          end
        end

        # Handle {% if variable != value %}...{% endif %}
        result = result.gsub(/\{%\s*if\s+(\w+)\s*!=\s*["']?([^"'\s}]+)["']?\s*%\}(.*?)\{%\s*endif\s*%\}/m) do |_match, io|
          var_name = io[1].strip
          expected_value = io[2].strip
          content = io[3]

          value = context[var_name]?
          actual_value = value.try(&.as_s) || ""

          if actual_value != expected_value
            content
          else
            ""
          end
        end

        result
      end

      # Check if a JSON::Any value is truthy
      private def self.truthy?(value : JSON::Any?) : Bool
        return false if value.nil?

        case value.raw
        when Bool
          value.as_bool
        when String
          !value.as_s.empty?
        when Int64, Int32
          value.as_i != 0
        when Float64
          value.as_f != 0.0
        when Array
          !value.as_a.empty?
        when Hash
          !value.as_h.empty?
        when Nil
          false
        else
          true
        end
      end
    end
  end
end
