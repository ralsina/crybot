module Crybot
  module Channels
    class Registry
      @@telegram : TelegramChannel?

      def self.register_telegram(channel : TelegramChannel)
        @@telegram = channel
      end

      def self.telegram : TelegramChannel?
        @@telegram
      end

      def self.clear_telegram
        @@telegram = nil
      end
    end
  end
end
