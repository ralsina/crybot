require "log"
require "../config/loader"
require "../agent/loop"
require "./telegram"
require "./telegram_adapter"
require "./unified_registry"

module Crybot
  module Channels
    class Manager
      @config : Config::ConfigFile
      @agent : Agent::Loop
      @channels : Array(TelegramChannel) = [] of TelegramChannel

      def initialize(@config : Config::ConfigFile)
        Log.info { "[Channels] Initializing agent..." }
        @agent = Agent::Loop.new(@config)
        Log.info { "[Channels] Agent initialized" }
      end

      def start : Nil
        started = [] of String

        if @config.channels.telegram.enabled?
          if @config.channels.telegram.token.empty?
            Log.warn { "[Channels] Telegram enabled but no token configured" }
          else
            Log.info { "[Channels] Creating Telegram channel..." }
            telegram = TelegramChannel.new(@config.channels.telegram, @agent)
            @channels << telegram

            # Register with unified registry
            adapter = TelegramAdapter.new(telegram)
            UnifiedRegistry.register(adapter)

            started << "Telegram"
            Log.info { "[Channels] Telegram channel created and registered" }
          end
        end

        if started.empty?
          Log.warn { "[Channels] No channels enabled. Enable channels in config.yml" }
          return
        end

        Log.info { "[Channels] Starting channels: #{started.join(", ")}" }

        # Start each channel in a fiber so they don't block
        @channels.each do |channel|
          spawn do
            begin
              Log.info { "[Channels] Starting channel fiber..." }
              channel.start
              Log.info { "[Channels] Channel fiber completed" }
            rescue e : Exception
              Log.error(exception: e) { "[Channels] Error in channel: #{e.message}" }
            end
          end
        end
      end

      def stop : Nil
        @channels.each(&.stop)
        @channels.clear
      end
    end
  end
end
