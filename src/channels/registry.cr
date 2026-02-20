require "log"

module Crybot
  module Channels
    class Registry
      @@telegram : TelegramChannel?

      def self.register_telegram(channel : TelegramChannel)
        @@telegram = channel
        Log.info { "[Channels::Registry] Telegram channel registered" }
      end

      def self.telegram : TelegramChannel?
        result = @@telegram
        if result.nil?
          Log.debug { "[Channels::Registry] Telegram channel requested but not registered" }
        else
          Log.debug { "[Channels::Registry] Telegram channel found" }
        end
        result
      end

      def self.clear_telegram
        Log.info { "[Channels::Registry] Telegram channel cleared" }
        @@telegram = nil
      end
    end
  end
end
