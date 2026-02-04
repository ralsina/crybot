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

          # Check if this is MCP-only update (which has special handling)
          if data.as_h.keys == ["mcp"] && data["mcp"]?.try(&.as_h?) && data["mcp"].as_h.keys == ["servers"]
            # MCP-only update, use the special handler
            new_config = apply_config_changes(current_config, data)
            # For MCP, the file is already written inside apply_config_changes
            # Just need to reload and return success
            Config::Loader.reload
            env.response.status_code = 200
            {success: true, message: "Configuration updated"}.to_json
          else
            # Regular config update
            new_config = apply_config_changes(current_config, data)

            # Convert to YAML
            yaml_content = new_config.to_yaml

            # Save to config file
            File.write(Config::Loader.config_file, yaml_content)

            # Reload config
            Config::Loader.reload

            env.response.status_code = 200
            {success: true, message: "Configuration updated"}.to_json
          end
        rescue e : Exception
          env.response.status_code = 400
          {success: false, error: e.message}.to_json
        end

        private def mask_sensitive_values(config : Config::ConfigFile)
          result = {
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
            "mcp" => {
              "servers" => JSON::Any.new(config.mcp.servers.map { |server|
                server_hash = {
                  "name"    => JSON::Any.new(server.name),
                  "command" => server.command ? JSON::Any.new(server.command) : JSON::Any.new(""),
                  "url"     => server.url ? JSON::Any.new(server.url) : JSON::Any.new(""),
                }
                JSON::Any.new(server_hash)
              }),
            },
          }

          # Add voice config if present
          if voice_config = config.voice
            result["voice"] = {
              "wake_word"              => JSON::Any.new(voice_config.wake_word || ""),
              "whisper_stream_path"    => JSON::Any.new(voice_config.whisper_stream_path || ""),
              "model_path"             => JSON::Any.new(voice_config.model_path || ""),
              "language"               => JSON::Any.new(voice_config.language || ""),
              "threads"                => JSON::Any.new(voice_config.threads || 4),
              "piper_model"            => JSON::Any.new(voice_config.piper_model || ""),
              "piper_path"             => JSON::Any.new(voice_config.piper_path || ""),
              "conversational_timeout" => JSON::Any.new(voice_config.conversational_timeout || 3),
              "step_ms"                => JSON::Any.new(voice_config.step_ms),
              "audio_length_ms"        => JSON::Any.new(voice_config.audio_length_ms),
              "audio_keep_ms"          => JSON::Any.new(voice_config.audio_keep_ms),
              "vad_threshold"          => JSON::Any.new(voice_config.vad_threshold),
            }
          end

          result
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

          # Apply MCP config changes by rebuilding the config YAML
          if mcp_data = data["mcp"]?
            if servers_data = mcp_data["servers"]?.try(&.as_a?)
              # Load current config as YAML
              yaml_content = File.read(Config::Loader.config_file)
              yaml_hash = YAML.parse(yaml_content).as_h

              # Update MCP servers
              new_servers = [] of YAML::Any
              servers_data.each do |server_obj|
                server_hash = server_obj.as_h
                name = server_hash["name"]?.try(&.as_s) || next

                new_server_hash = {} of YAML::Any => YAML::Any
                new_server_hash[YAML::Any.new("name")] = YAML::Any.new(name)

                # Handle command - can be string or null
                command_value = server_hash["command"]?
                if command_value
                  if command_str = command_value.as_s?
                    new_server_hash[YAML::Any.new("command")] = YAML::Any.new(command_str) unless command_str.empty?
                  end
                end

                # Handle url - can be string or null
                url_value = server_hash["url"]?
                if url_value
                  if url_str = url_value.as_s?
                    new_server_hash[YAML::Any.new("url")] = YAML::Any.new(url_str) unless url_str.empty?
                  end
                end

                new_servers << YAML::Any.new(new_server_hash)
              end

              mcp_hash = {} of YAML::Any => YAML::Any
              mcp_hash[YAML::Any.new("servers")] = YAML::Any.new(new_servers)
              yaml_hash[YAML::Any.new("mcp")] = YAML::Any.new(mcp_hash)

              # Write back to config
              File.write(Config::Loader.config_file, yaml_hash.to_yaml)

              # Reload config
              return Config::Loader.load
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
