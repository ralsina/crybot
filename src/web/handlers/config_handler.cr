require "json"
require "yaml"
require "../../config/schema"
require "../../config/loader"

module Crybot
  module Web
    module Handlers
      class ConfigHandler
        def initialize(@config : Config::ConfigFile)
        end

        # GET /api/config - Get current config (masked)
        def get_config(env) : String
          masked_config = mask_sensitive_values(@config)
          masked_config.to_json
        end

        # PUT /api/config - Update config
        def update_config(env) : String
          body = env.request.body.try(&.gets_to_end) || ""

          # Parse as JSON first (from frontend)
          data = JSON.parse(body)

          # Load current config
          current_config = Config::Loader.load

          # Apply changes
          new_config = apply_config_changes(current_config, data)

          # Convert to YAML
          yaml_content = new_config.to_yaml

          # Save to config file
          File.write(Config::Loader.config_file, yaml_content)

          # Reload config
          Config::Loader.reload

          env.response.status_code = 200
          {success: true, message: "Configuration updated"}.to_json
        rescue e : Exception
          env.response.status_code = 400
          {success: false, error: e.message}.to_json
        end

        private def mask_sensitive_values(config : Config::ConfigFile)
          {
            "web" => {
              "enabled"         => JSON::Any.new(config.web.enabled?),
              "host"            => JSON::Any.new(config.web.host),
              "port"            => JSON::Any.new(config.web.port),
              "path_prefix"     => JSON::Any.new(config.web.path_prefix),
              "auth_token"      => mask_value(config.web.auth_token),
              "allowed_origins" => JSON::Any.new(config.web.allowed_origins.map { |v| JSON::Any.new(v) }),
              "enable_cors"     => JSON::Any.new(config.web.enable_cors?),
            },
            "agents" => {
              "defaults" => {
                "model"               => JSON::Any.new(config.agents.defaults.model),
                "max_tokens"          => JSON::Any.new(config.agents.defaults.max_tokens),
                "temperature"         => JSON::Any.new(config.agents.defaults.temperature),
                "max_tool_iterations" => JSON::Any.new(config.agents.defaults.max_tool_iterations),
              },
            },
            "providers" => {
              "zhipu"      => {"api_key" => mask_value(config.providers.zhipu.api_key)},
              "openai"     => {"api_key" => mask_value(config.providers.openai.api_key)},
              "anthropic"  => {"api_key" => mask_value(config.providers.anthropic.api_key)},
              "openrouter" => {"api_key" => mask_value(config.providers.openrouter.api_key)},
              "vllm"       => {
                "api_key"  => mask_value(config.providers.vllm.api_key),
                "api_base" => JSON::Any.new(config.providers.vllm.api_base),
              },
            },
            "channels" => {
              "telegram" => {
                "enabled"    => JSON::Any.new(config.channels.telegram.enabled),
                "token"      => mask_value(config.channels.telegram.token),
                "allow_from" => JSON::Any.new(config.channels.telegram.allow_from.map { |v| JSON::Any.new(v) }),
              },
            },
          }
        end

        private def mask_value(value : String) : JSON::Any
          if value.empty?
            JSON::Any.new("")
          else
            JSON::Any.new("******")
          end
        end

        private def apply_config_changes(config : Config::ConfigFile, data : JSON::Any) : Config::ConfigFile
          # Apply web config changes
          if web_data = data["web"]?
            if enabled = web_data["enabled"]?
              config = config.with_web(config.web.with_enabled(enabled.as_bool))
            end
            if host = web_data["host"]?
              config = config.with_web(config.web.with_host(host.as_s))
            end
            if port = web_data["port"]?
              config = config.with_web(config.web.with_port(port.as_i))
            end
            if auth_token = web_data["auth_token"]?
              # Don't overwrite with masked value
              if auth_token.as_s != "******"
                config = config.with_web(config.web.with_auth_token(auth_token.as_s))
              end
            end
          end

          # Note: agents config changes would require similar with_* methods on AgentsConfig
          # For now, we'll skip those changes

          config
        end
      end
    end
  end
end
