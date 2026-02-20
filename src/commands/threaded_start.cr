require "log"
require "../config/loader"
require "../landlock_socket"
require "../agent/tool_monitor"
require "../agent/tools/registry"
require "../http_proxy/server"
require "../scheduled_tasks/feature"
require "../channels/manager"
require "../features/gateway"

module Crybot
  module Commands
    # Threaded start command - runs agent and tool monitor fibers
    #
    # Architecture:
    # - Single process, no Landlock on main process
    # - Tool monitor fiber: spawns landlocked subprocesses for tool execution
    # - Agent loop fiber: runs LLM and agent features
    # - Landlock access monitor: handles user prompts for access requests
    class ThreadedStart
      # Use a forward reference to avoid circular dependency
      alias AgentLoop = ::Crybot::Agent::Loop

      def self.execute : Nil
        # Start the Landlock access monitor server (for rofi/terminal prompts)
        Log.info { "[Crybot] Starting Landlock access monitor..." }
        LandlockSocket.start_monitor_server

        # Load configuration early
        config = Config::Loader.load
        config = Config::Loader.migrate_config(config)

        # Start HTTP proxy if enabled
        if config.proxy.enabled?
          Log.info { "[Crybot] Starting HTTP proxy..." }
          HttpProxy::Server.start
        end

        # Start the tool execution monitor fiber
        Log.info { "[Crybot] Starting tool execution monitor..." }
        ToolMonitor.start_monitor

        # Enable monitor mode for tools (routes through tool monitor)
        Tools::Registry.enable_monitor_mode

        # Start the agent loop
        Log.info { "[Crybot] Starting agent loop..." }
        run_agent_loop(config)

        # Setup signal handlers for graceful shutdown
        setup_signal_handlers

        # Keep main thread alive while fibers run
        Log.info { "[Crybot] All fibers started. Press Ctrl+C to stop" }
        keep_alive
      end

      private def self.run_agent_loop(config : Config::ConfigFile) : Nil
        # Spawn the agent fiber
        spawn_agent_fiber(config)
      end

      # Spawn a new agent fiber
      private def self.spawn_agent_fiber(config : Config::ConfigFile) : Fiber
        spawn do
          begin
            Log.info { "[Agent] Starting... (tools run in landlocked subprocesses)" }

            # Create agent loop
            agent_loop = AgentLoop.new(config)

            # Start normal agent features
            start_agent_features(config, agent_loop)

            Log.info { "[Agent] Exiting" }
          rescue e : Exception
            Log.error(exception: e) { "[Agent] Error: #{e.message}" }
            Log.debug(exception: e) { e.backtrace.join("\n") } if ENV["DEBUG"]?
          end
        end
      end

      private def self.start_agent_features(config : Config::ConfigFile, agent_loop : AgentLoop) : Nil
        # Check if any features are enabled
        features_config = config.features

        # Start gateway feature (Telegram) if enabled (runs in background fiber)
        if features_config.gateway
          Log.info { "[Agent] Starting gateway feature..." }
          gateway_feature = Features::GatewayFeature.new(config)
          spawn do
            begin
              gateway_feature.start
            rescue e : Exception
              Log.error(exception: e) { "[Agent] Gateway error: #{e.message}" }
            end
          end
        end

        # Start scheduled tasks feature if enabled (runs in background fiber)
        if features_config.scheduled_tasks
          Log.info { "[Agent] Starting scheduled tasks feature..." }
          scheduled_tasks_feature = ScheduledTasks::Feature.new(config, agent_loop)
          spawn do
            begin
              scheduled_tasks_feature.start
            rescue e : Exception
              Log.error(exception: e) { "[Agent] Scheduled tasks error: #{e.message}" }
            end
          end
        end

        if features_config.repl
          Log.info { "[Agent] Starting REPL feature..." }
          # Start REPL - this will block until REPL exits
          Features::ReplFeature.new(config).start
        elsif features_config.web
          Log.info { "[Agent] Starting web feature..." }
          # Start web server
          Features::WebFeature.new(config).start(agent_loop)
        else
          Log.warn { "[Agent] No interactive features enabled." }
          Log.info { "[Agent] Enable 'repl' or 'web' in config.yml" }
        end
      end

      private def self.setup_signal_handlers : Nil
        # Handle SIGINT (Ctrl+C)
        Signal::INT.trap do
          Log.info { "\n[Crybot] Shutting down..." }
          exit 0
        end

        # Handle SIGTERM
        Signal::TERM.trap do
          Log.info { "\n[Crybot] Received shutdown signal" }
          exit 0
        end
      end

      private def self.keep_alive : Nil
        # Keep the main thread alive
        sleep
      end
    end
  end
end
