require "markd"

module Crybot
  module Channels
    # Unified message format for all channels
    class ChannelMessage
      property chat_id : String
      property content : String
      property role : String # "user" or "assistant"
      property format : MessageFormat?
      property parse_mode : Symbol? # :markdown, :html, or nil
      property metadata : Hash(String, String)?

      enum MessageFormat
        Plain
        Markdown
        HTML
      end

      def initialize(@chat_id : String, @content : String, @role : String = "assistant", @format : MessageFormat? = nil, @parse_mode : Symbol? = nil, @metadata : Hash(String, String)? = nil)
      end

      # Convert message content to a different format
      def convert_to(target_format : MessageFormat) : String
        source_format = @format || MessageFormat::Markdown

        # No conversion needed if same format
        return @content if source_format == target_format

        case target_format
        when MessageFormat::HTML
          markdown_to_html
        when MessageFormat::Markdown
          html_to_markdown
        when MessageFormat::Plain
          to_plain_text
        else
          @content
        end
      end

      # Get content in the channel's preferred format
      def content_for_channel(channel : Channel) : String
        if channel.supports_html? && @format == MessageFormat::Markdown
          convert_to(MessageFormat::HTML)
        elsif channel.supports_markdown? && @format == MessageFormat::HTML
          convert_to(MessageFormat::Markdown)
        else
          @content
        end
      end

      private def markdown_to_html : String
        Markd.to_html(@content)
      end

      private def html_to_markdown : String
        # Simple HTML to Markdown conversion
        # This is a basic implementation - for production use a proper library would be better
        @content
          .gsub(/<b>(.*?)<\/b>/i) { "**#{$1}**" }
          .gsub(/<strong>(.*?)<\/strong>/i) { "**#{$1}**" }
          .gsub(/<i>(.*?)<\/i>/i) { "*#{$1}*" }
          .gsub(/<em>(.*?)<\/em>/i) { "*#{$1}*" }
          .gsub(/<code>(.*?)<\/code>/i) { "`#{$1}`" }
          .gsub(/<pre>(.*?)<\/pre>/im) { "```\n#{$1}\n```" }
          .gsub(/<h1>(.*?)<\/h1>/i) { "# #{$1}" }
          .gsub(/<h2>(.*?)<\/h2>/i) { "## #{$1}" }
          .gsub(/<h3>(.*?)<\/h3>/i) { "### #{$1}" }
          .gsub(/<br\s*\/?>/, "\n")
          .gsub(/<\/p>/, "\n\n")
          .gsub(/<p>/, "")
          .gsub(/<[^>]+>/, "") # Remove remaining HTML tags
      end

      private def to_plain_text : String
        # Strip all formatting
        case @format
        when MessageFormat::HTML
          @content.gsub(/<[^>]+>/, "").strip
        when MessageFormat::Markdown
          @content
            .gsub(/\*\*(.*?)\*\*/, "\\1") # Bold
            .gsub(/\*(.*?)\*/, "\\1")     # Italic
            .gsub(/`(.*?)`/, "\\1")       # Inline code
            .gsub(/```[\s\S]*?```/, "")   # Code blocks
            .gsub(/^#+\s/, "")            # Headers
            .strip
        else
          @content
        end
      end
    end

    # Abstract base class for all conversation channels
    # All channels (Telegram, Web, Voice, REPL, etc.) should implement this interface
    abstract class Channel
      # Channel identifier (e.g., "telegram", "web", "voice", "repl")
      abstract def name : String

      # Start the channel (begin listening for messages)
      abstract def start : Nil

      # Stop the channel (stop listening for messages)
      abstract def stop : Nil

      # Send a message to a specific chat/session
      abstract def send_message(message : ChannelMessage) : Nil

      # Get the session key for a given chat_id
      # Session keys follow the pattern: "channel:chat_id"
      def session_key(chat_id : String) : String
        "#{name}:#{chat_id}"
      end

      # Optional: Channel capabilities
      def supports_markdown? : Bool
        false
      end

      def supports_html? : Bool
        false
      end

      # Preferred format for this channel
      def preferred_format : ChannelMessage::MessageFormat
        if supports_html?
          ChannelMessage::MessageFormat::HTML
        elsif supports_markdown?
          ChannelMessage::MessageFormat::Markdown
        else
          ChannelMessage::MessageFormat::Plain
        end
      end

      def max_message_length : Int32
        4096
      end

      # Optional: Channel-specific configuration validation
      def validate_config(config : Hash(String, JSON::Any)) : Bool
        true
      end

      # Optional: Channel health check
      def healthy? : Bool
        true
      end

      # Truncate message to max length if needed
      protected def truncate_message(content : String) : String
        max_len = max_message_length
        if content.size > max_len
          content[0...max_len] + "\n\n... (truncated)"
        else
          content
        end
      end
    end
  end
end
