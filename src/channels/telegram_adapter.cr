require "../channels/channel"
require "../channels/unified_registry"

module Crybot
  module Channels
    # Adapter that wraps the existing TelegramChannel to implement the Channel interface
    class TelegramAdapter < Channel
      @telegram_channel : ::TelegramChannel

      def initialize(@telegram_channel : ::TelegramChannel)
      end

      def name : String
        "telegram"
      end

      def start : Nil
        @telegram_channel.start
      end

      def stop : Nil
        @telegram_channel.stop
      end

      def send_message(message : ChannelMessage) : Nil
        # Convert message content to the channel's preferred format
        # Telegram supports both Markdown and HTML - prefer Markdown
        content = message.content_for_channel(self)

        # Truncate if needed
        content = truncate_message(content)

        # Determine parse_mode based on message format
        parse_mode = if message.format == ChannelMessage::MessageFormat::HTML
                       :html
                     else
                       :markdown
                     end

        @telegram_channel.send_to_chat(message.chat_id, content, parse_mode)
      end

      def supports_markdown? : Bool
        true
      end

      def supports_html? : Bool
        true
      end

      def max_message_length : Int32
        4096
      end

      def healthy? : Bool
        # Telegram is healthy if the channel is still running
        # We can check if it's registered in the old registry
        ::Registry.telegram != nil
      end
    end
  end
end
