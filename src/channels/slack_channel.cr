require "slack"
require "./channel"
require "../agent/loop"
require "../session/manager"

module Crybot
  module Channels
    # Slack channel - handles Slack bot interactions via Socket Mode
    # Uses the jgaskins/slack library for WebSocket-based communication
    class SlackChannel < Channel
      @client : Slack::SocketAPIClient
      @agent : Agent::Loop
      @api_client : Slack::API::Client
      @running : Bool = true
      @sessions : Session::Manager

      getter agent, api_client

      def initialize(config : Config::ChannelsConfig::SlackConfig, agent : Agent::Loop)
        @agent = agent
        @sessions = Session::Manager.instance

        # Create API client for sending messages
        @api_client = Slack::API::Client.new(config.api_token)

        # Create Socket Mode client for receiving messages
        socket_token = config.socket_token.empty? ? ENV["SLACK_SOCKET_TOKEN"]? : config.socket_token
        if socket_token.nil? || socket_token.empty?
          raise "Slack socket token not configured. Set SLACK_SOCKET_TOKEN environment variable or configure slack.socket_token in config.yml"
        end

        @client = Slack::SocketAPIClient.new(socket_token: socket_token, api_token: config.api_token)

        puts "[Slack] Slack client initialized"
      end

      def name : String
        "slack"
      end

      def start : Nil
        puts "[Slack] Starting Socket Mode connection..."

        # Start the Slack client in a fiber
        spawn do
          begin
            @client.start
          rescue e : Exception
            puts "[Slack] Error in client: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end

        @running = true
        puts "[Slack] Connected and listening for events"
      end

      def stop : Nil
        @running = false
        @client.close
        puts "[Slack] Disconnected"
      end

      def send_message(message : ChannelMessage) : Nil
        # Send message via Slack API
        channel_id = message.chat_id

        # Convert content to Slack's format (they support markdown-like formatting)
        content = message.content

        begin
          @api_client.chat.post_message(
            channel: channel_id,
            text: content
          )
        rescue e : Exception
          puts "[Slack] Error sending message: #{e.message}"
        end
      end

      def session_key(chat_id : String) : String
        # Slack sessions use the pattern "slack:CHANNEL_ID"
        "#{name}:#{chat_id}"
      end

      def supports_markdown? : Bool
        true
      end

      def max_message_length : Int32
        # Slack has a 40,000 character limit for messages
        40000
      end

      # Event handlers for Slack events

      def received(message : Slack::Message)
        return unless @running

        # Only process messages that aren't from bots
        return if message.bot_id?
        return if message.subtype?

        # Get channel ID and text content
        channel_id = message.channel
        text = message.text || ""

        # Skip empty messages
        return if text.empty?

        # Create session key
        session_key = session_key(channel_id)

        puts "[Slack] Received message from #{channel_id}: #{text[0...100]}"

        # Process the message through the agent
        spawn do
          begin
            @agent.process(session_key, text)
          rescue e : Exception
            puts "[Slack] Error processing message: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end
      end

      def received(mention : Slack::AppMention)
        return unless @running

        # Extract command text (remove the bot mention)
        text = mention.text || ""
        command_text = text.gsub(/\A<@\w+> /, "")

        channel_id = mention.channel
        session_key = session_key(channel_id)

        puts "[Slack] Received mention from #{channel_id}: #{command_text[0...100]}"

        # Process the mention through the agent
        spawn do
          begin
            @agent.process(session_key, command_text)
          rescue e : Exception
            puts "[Slack] Error processing mention: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end
      end

      def received(event : Slack::Hello)
        puts "[Slack] Connected to Slack workspace"
      end

      def received(event : Slack::Error)
        puts "[Slack] Error received: #{event.error.inspect}"
      end

      # Catch-all for unknown events
      def received(event)
        # Log unknown events for debugging
        puts "[Slack] Received event: #{event.class}" if ENV["DEBUG"]?
      end

      def healthy? : Bool
        @running && @client.state.connected?
      end
    end
  end
end
