module Crybot
  module Channels
    # Unified channel registry for managing all conversation channels
    # This replaces the old telegram-specific registry
    class UnifiedRegistry
      @@channels = Hash(String, Channel).new

      # Register a channel
      def self.register(channel : Channel) : Nil
        @@channels[channel.name] = channel
        puts "[ChannelRegistry] Registered channel: #{channel.name}"
      end

      # Get a channel by name
      def self.get(name : String) : Channel?
        @@channels[name]?
      end

      # Get all registered channels
      def self.all : Array(Channel)
        @@channels.values
      end

      # Check if a channel is registered
      def self.registered?(name : String) : Bool
        @@channels.has_key?(name)
      end

      # Unregister a channel
      def self.unregister(name : String) : Channel?
        @@channels.delete(name)
      end

      # Send a message to any registered channel with automatic format conversion
      # The message will be converted to the channel's preferred format if needed
      def self.send_to_channel(channel_name : String, chat_id : String, content : String, format : ChannelMessage::MessageFormat = :markdown) : Bool
        channel = get(channel_name)
        return false unless channel

        message = ChannelMessage.new(
          chat_id: chat_id,
          content: content,
          role: "assistant",
          format: format,
        )

        channel.send_message(message)
        true
      rescue e : Exception
        puts "[ChannelRegistry] Failed to send to #{channel_name}: #{e.message}"
        false
      end

      # Send a message with explicit parse_mode (for backward compatibility)
      def self.send_to_channel(channel_name : String, chat_id : String, content : String, parse_mode : Symbol?) : Bool
        # Convert parse_mode symbol to MessageFormat
        format = case parse_mode
                 when :markdown then ChannelMessage::MessageFormat::Markdown
                 when :html     then ChannelMessage::MessageFormat::HTML
                 else                ChannelMessage::MessageFormat::Plain
                 end

        send_to_channel(channel_name, chat_id, content, format)
      end

      # Get health status of all channels
      def self.health_status : Hash(String, Bool)
        @@channels.transform_values(&.healthy?)
      end

      # Start all registered channels
      def self.start_all : Nil
        @@channels.each do |name, channel|
          begin
            channel.start
          rescue e : Exception
            puts "[ChannelRegistry] Failed to start #{name}: #{e.message}"
          end
        end
      end

      # Stop all registered channels
      def self.stop_all : Nil
        @@channels.each do |name, channel|
          begin
            channel.stop
          rescue e : Exception
            puts "[ChannelRegistry] Failed to stop #{name}: #{e.message}"
          end
        end
      end

      # Clear all channels (mainly for testing)
      def self.clear : Nil
        @@channels.clear
      end
    end
  end
end
