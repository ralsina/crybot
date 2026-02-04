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
        puts "[#{Time.local.to_s("%H:%M:%S")}] Initializing agent..."
        @agent = Agent::Loop.new(@config)
        puts "[#{Time.local.to_s("%H:%M:%S")}] Agent initialized"
      end

      def start : Nil
        started = [] of String

        if @config.channels.telegram.enabled
          if @config.channels.telegram.token.empty?
            puts "Warning: Telegram enabled but no token configured"
          else
            puts "[#{Time.local.to_s("%H:%M:%S")}] Creating Telegram channel..."
            telegram = TelegramChannel.new(@config.channels.telegram, @agent)
            @channels << telegram

            # Register with unified registry
            adapter = TelegramAdapter.new(telegram)
            UnifiedRegistry.register(adapter)

            started << "Telegram"
            puts "[#{Time.local.to_s("%H:%M:%S")}] Telegram channel created and registered"
          end
        end

        if started.empty?
          puts "No channels enabled. Enable channels in config.yml"
          return
        end

        puts "Starting channels: #{started.join(", ")}"
        puts "Press Ctrl+C to stop"

        # Start first channel (blocking)
        # For multiple channels, we'd use fibers/spawn
        @channels.first.start
      end

      def stop : Nil
        @channels.each(&.stop)
        @channels.clear
      end
    end
  end
end
