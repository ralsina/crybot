require "./channel"

module Crybot
  module Channels
    # REPL channel - handles interactive terminal sessions
    # Messages are printed to console with formatting
    class ReplChannel < Channel
      def initialize
      end

      def name : String
        "repl"
      end

      def start : Nil
        # REPL is started separately by ReplFeature
        # This is a no-op for the channel adapter
      end

      def stop : Nil
        # REPL is stopped separately
      end

      def send_message(message : ChannelMessage) : Nil
        # Get content and format for console output
        content = message.content_for_channel(self)

        # Print to console with appropriate formatting
        print_message(content)
      end

      def session_key(chat_id : String) : String
        # REPL uses a single shared session
        "repl"
      end

      def supports_markdown? : Bool
        true # Console can display markdown-style formatting
      end

      def preferred_format : ChannelMessage::MessageFormat
        ChannelMessage::MessageFormat::Markdown
      end

      private def print_message(content : String) : Nil
        # Simple console output with basic formatting
        # For a more advanced version, we could use a terminal coloring library

        # Add basic ANSI coloring
        colored = content
          .gsub(/\*\*(.*?)\*\*/, "\e[1m\\1\e[0m") # Bold
          .gsub(/\*(.*?)\*/, "\e[3m\\1\e[0m")     # Italic
          .gsub(/`(.*?)`/, "\e[36m\\1\e[0m")      # Code (cyan)

        puts "\n#{colored}\n"
      end
    end
  end
end
