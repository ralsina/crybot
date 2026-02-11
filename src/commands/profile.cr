require "log"
require "../config/loader"
require "../agent/loop"
require "kemal"

module Crybot
  module Commands
    class Profile
      def self.execute : Nil
        Log.info { "[1] Starting profile..." }
        total_start = Time.instant

        # 1. Load config
        config_start = Time.instant
        config = Config::Loader.load
        config = Config::Loader.migrate_config(config)
        config_time = (Time.instant - config_start).total_milliseconds
        Log.info { "Config load: #{config_time.round(2)}ms" }

        # 2. Create agent loop (this loads skills, MCP, etc.)
        Log.info { "[2] Creating agent loop..." }
        agent_start = Time.instant
        _agent_loop = Crybot::Agent::Loop.new(config)
        agent_time = (Time.instant - agent_start).total_milliseconds
        Log.info { "Agent loop init: #{agent_time.round(2)}ms" }
        Log.info { "[3] Agent loop created" }

        # 3. Start Kemal in a fiber and measure time
        Log.info { "[4] Starting Kemal..." }
        kemal_start = Time.instant

        # Start Kemal in a background fiber
        _kemal_fiber = spawn do
          Kemal.config.port = 3003
          Kemal.config.host_binding = "0.0.0.0"
          Log.debug { "[5] Kemal about to run..." }
          Kemal.run
        end

        # Give Kemal a moment to start
        sleep 0.5.seconds
        Log.info { "[6] Kemal started" }

        kemal_time = (Time.instant - kemal_start).total_milliseconds
        Log.info { "Kemal start: #{kemal_time.round(2)}ms" }

        total = (Time.instant - total_start).total_milliseconds
        Log.info { "" }
        Log.info { "Total startup: #{total.round(2)}ms" }

        # Keep it running briefly
        Log.info { "Running for 2 seconds..." }
        sleep 2.seconds
      end
    end
  end
end
