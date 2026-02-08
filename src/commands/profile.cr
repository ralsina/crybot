require "../config/loader"
require "../agent/loop"
require "kemal"

module Crybot
  module Commands
    class Profile
      def self.execute : Nil
        puts "[1] Starting profile..."
        total_start = Time.instant

        # 1. Load config
        config_start = Time.instant
        config = Config::Loader.load
        config = Config::Loader.migrate_config(config)
        config_time = (Time.instant - config_start).total_milliseconds
        puts "Config load: #{config_time.round(2)}ms"

        # 2. Create agent loop (this loads skills, MCP, etc.)
        puts "[2] Creating agent loop..."
        agent_start = Time.instant
        agent_loop = Crybot::Agent::Loop.new(config)
        agent_time = (Time.instant - agent_start).total_milliseconds
        puts "Agent loop init: #{agent_time.round(2)}ms"
        puts "[3] Agent loop created"

        # 3. Start Kemal in a fiber and measure time
        puts "[4] Starting Kemal..."
        kemal_start = Time.instant

        # Start Kemal in a background fiber
        kemal_fiber = spawn do
          Kemal.config.port = 3003
          Kemal.config.host_binding = "0.0.0.0"
          puts "[5] Kemal about to run..."
          Kemal.run
        end

        # Give Kemal a moment to start
        sleep 0.5.seconds
        puts "[6] Kemal started"

        kemal_time = (Time.instant - kemal_start).total_milliseconds
        puts "Kemal start: #{kemal_time.round(2)}ms"

        total = (Time.instant - total_start).total_milliseconds
        puts "\nTotal startup: #{total.round(2)}ms"

        # Keep it running briefly
        puts "Running for 2 seconds..."
        sleep 2.seconds
      end
    end
  end
end
