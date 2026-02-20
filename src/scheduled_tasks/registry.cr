require "log"
require "../config/loader"

module Crybot
  module ScheduledTasks
    class Registry
      class_getter instance : Registry = Registry.new

      @feature : Feature?
      @config : Config::ConfigFile?

      def register(feature : Feature) : Nil
        @feature = feature
      end

      def feature : Feature?
        @feature
      end

      def feature! : Feature
        if f = @feature
          Log.debug { "[ScheduledTasks] Registry: Returning cached feature (#{f.tasks.size} tasks)" }
          return f
        end

        # Lazily create feature if not registered
        # This allows web UI to work even when running via web feature only
        Log.info { "[ScheduledTasks] Registry: No cached feature, creating new one..." }
        begin
          config = @config ||= Config::Loader.load
          agent_loop = Agent::Loop.new(config)
          feature = Feature.new(config, agent_loop)
          feature.load_tasks_from_disk # Load tasks from disk
          @feature = feature
          Log.info { "[ScheduledTasks] Lazily created feature instance for web access (loaded #{feature.tasks.size} tasks)" }
          feature
        rescue e : Exception
          Log.error(exception: e) { "[ScheduledTasks] Failed to create feature: #{e.message}" }
          raise RuntimeError.new("Failed to initialize ScheduledTasks feature: #{e.message}")
        end
      end

      def config=(config : Config::ConfigFile) : Nil
        @config = config
      end
    end
  end
end
