require "whatsapp"
require "./channel"
require "../agent/loop"
require "../session/manager"

module Crybot
  module Channels
    # WhatsApp channel - handles WhatsApp bot interactions via Cloud API
    # Uses the whatsapp shard for Meta's WhatsApp Cloud API integration
    class WhatsAppChannel < Channel
      @client : WhatsApp::Client
      @agent : Agent::Loop
      @verify_token : String
      @app_secret : String
      @running : Bool = true
      @sessions : Session::Manager

      getter agent, verify_token

      def initialize(config : Config::ChannelsConfig::WhatsAppConfig, agent : Agent::Loop)
        @agent = agent
        @sessions = Session::Manager.instance
        @verify_token = config.webhook_verify_token
        @app_secret = config.app_secret

        # Create WhatsApp Cloud API client
        @client = WhatsApp::Client.new(
          phone_number_id: config.phone_number_id,
          access_token: config.access_token
        )

        puts "[WhatsApp] WhatsApp client initialized"
      end

      def name : String
        "whatsapp"
      end

      def start : Nil
        puts "[WhatsApp] Webhook channel started"
        puts "[WhatsApp] Configure webhook URL: #{@client.webhook_url}"
        puts "[WhatsApp] Verify token: #{@verify_token}"
        @running = true
      end

      def stop : Nil
        @running = false
        puts "[WhatsApp] Webhook channel stopped"
      end

      def send_message(message : ChannelMessage) : Nil
        # Send message via WhatsApp Cloud API
        phone_number = message.chat_id

        # Convert content to plain text (WhatsApp supports basic formatting)
        content = message.content

        begin
          @client.send_text(
            to: phone_number,
            text: content
          )
        rescue e : Exception
          puts "[WhatsApp] Error sending message: #{e.message}"
        end
      end

      def session_key(chat_id : String) : String
        # WhatsApp sessions use the pattern "whatsapp:PHONE_NUMBER"
        "#{name}:#{chat_id}"
      end

      # Check if this is a webhook channel (no direct connection)
      def webhook_based? : Bool
        true
      end

      # Verify a webhook request from Meta
      def verify_webhook(mode : String?, token : String?) : Bool
        WhatsApp::Webhook.verify?(mode, token, @verify_token)
      end

      # Verify webhook signature
      def valid_webhook_signature?(headers : HTTP::Headers, body : String) : Bool
        WhatsApp::Webhook.valid_signature?(headers, body, @app_secret)
      end

      # Handle incoming webhook payload
      def handle_webhook(body : String) : Nil
        return unless @running

        payload = WhatsApp::Webhook.parse_payload(body)

        payload.each_entry do |entry|
          entry.each_change do |change|
            change.each_message do |message|
              process_message(message)
            end
          end
        end
      rescue e : Exception
        puts "[WhatsApp] Error processing webhook: #{e.message}"
        puts e.backtrace.join("\n") if ENV["DEBUG"]?
      end

      private def process_message(message : WhatsApp::Webhook::Message) : Nil
        # Only process text messages
        return unless message.text?

        phone_number = message.from
        text_obj = message.text
        return unless text_obj

        text_body = text_obj.body
        return unless text_body

        # Create session key
        session_key = session_key(phone_number)

        puts "[WhatsApp] Received message from #{phone_number}: #{text_body[0...100]}..."

        # Process the message through the agent
        spawn do
          begin
            @agent.process(session_key, text_body)
          rescue e : Exception
            puts "[WhatsApp] Error processing message: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end
      end

      def supports_markdown? : Bool
        false # WhatsApp has its own formatting
      end

      def healthy? : Bool
        @running
      end
    end
  end
end
