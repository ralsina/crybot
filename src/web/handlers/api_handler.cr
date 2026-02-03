require "json"
require "../../config/schema"
require "../../session/manager"

module Crybot
  module Web
    module Handlers
      class APIHandler
        def self.health(env) : String
          {
            status:    "ok",
            timestamp: Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"),
          }.to_json
        end

        def self.status(env, config : Config::ConfigFile, agent, sessions) : String
          {
            status:    "running",
            version:   "0.1.0",
            timestamp: Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"),
            config:    {
              web_enabled: config.web.enabled?,
              web_host:    config.web.host,
              web_port:    config.web.port,
              model:       config.agents.defaults.model,
            },
            sessions: {
              count: sessions.list_sessions.size,
            },
          }.to_json
        end
      end
    end
  end
end
