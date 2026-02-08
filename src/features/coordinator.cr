require "../config/loader"
require "../config/watcher"
require "../agent/loop"
require "./base"
require "./gateway"
require "./web"
require "./voice"
require "./repl"
require "../scheduled_tasks/feature"

module Crybot
  module Features
    class Coordinator
      @config : Config::ConfigFile
      @features : Array(FeatureModule) = [] of FeatureModule
      @agent_loop : Agent::Loop?
      @watcher : Config::Watcher?
      @running = true

      def initialize(@config : Config::ConfigFile)
      end

      def start : Nil
        return unless validate_configuration

        @agent_loop = Agent::Loop.new(@config)

        # Create and start enabled features
        create_and_start_features

        if @features.empty?
          puts "No features enabled. Enable features in config.yml under 'features:'"
          puts "Available features: gateway, web, voice, repl, scheduled_tasks"
          return
        end

        feature_names = @features.map do |feature|
          feature.class.name.gsub(/Crybot::Features::/, "").gsub(/Crybot::ScheduledTasks::/, "").gsub(/Feature$/, "")
        end
        puts "Started features: #{feature_names.join(", ")}"
        puts "Press Ctrl+C to stop"

        # Start config watcher for reload
        start_config_watcher

        # Setup signal handlers for graceful shutdown
        setup_signal_handlers

        # Main thread waits while features run in fibers
        wait_for_completion
      end

      def stop : Nil
        @running = false

        puts ""
        puts "Stopping features..."

        # Stop all features in reverse order
        @features.reverse_each do |feature|
          begin
            feature.stop
          rescue e : Exception
            puts "Error stopping #{feature.class.name}: #{e.message}"
          end
        end

        # Stop watcher
        if watcher = @watcher
          watcher.stop
        end

        puts "All features stopped"
      end

      private def create_and_start_features : Nil
        features_config = @config.features

        # Gateway feature (Telegram)
        if features_config.gateway
          feature = GatewayFeature.new(@config)
          @features << feature
          feature.start
        end

        # Web feature
        if features_config.web
          # Agent loop must be initialized before starting web feature
          unless @agent_loop
            @agent_loop = Agent::Loop.new(@config)
          end

          feature = WebFeature.new(@config)
          @features << feature
          feature.start(@agent_loop.not_nil!)
        end

        # Voice feature
        if features_config.voice
          feature = VoiceFeature.new(@config)
          @features << feature
          feature.start
        end

        # REPL feature
        if features_config.repl
          feature = ReplFeature.new(@config)
          @features << feature
          feature.start
        end

        # Scheduled Tasks feature
        if features_config.scheduled_tasks
          # Need agent loop for scheduled tasks
          agent_loop = @agent_loop || Agent::Loop.new(@config)
          feature = ScheduledTasks::Feature.new(@config, agent_loop)
          @features << feature
          feature.start
        end
      end

      private def validate_configuration : Bool
        # Check if at least one feature is enabled
        features_config = @config.features
        unless features_config.gateway || features_config.web || features_config.voice || features_config.repl || features_config.scheduled_tasks
          puts "Error: No features enabled."
          puts "Enable features in #{Config::Loader.config_file}"
          puts "\nExample:"
          puts "  features:"
          puts "    gateway: true"
          puts "    web: true"
          puts "    voice: false"
          puts "    repl: false"
          puts "    scheduled_tasks: false"
          return false
        end

        true
      end

      private def start_config_watcher : Nil
        watcher = Config::Watcher.new(Config::Loader.config_file, -> { restart })
        @watcher = watcher
        watcher.start
      end

      private def restart : Nil
        puts "[#{Time.local.to_s("%H:%M:%S")}] Config file changed, restarting..."

        # Stop the watcher
        if watcher = @watcher
          watcher.stop
        end

        # Re-exec the current process with the same arguments
        Process.exec(PROGRAM_NAME, ARGV)
      end

      private def setup_signal_handlers : Nil
        # Handle SIGINT (Ctrl+C)
        Signal::INT.trap do
          stop
          exit
        end

        # Handle SIGTERM
        Signal::TERM.trap do
          stop
          exit
        end
      end

      private def wait_for_completion : Nil
        # Keep the main thread alive while features run in fibers
        while @running
          sleep 1.second
        end
      end
    end
  end
end
