require "json"
require "openssl/hmac"

module WhatsApp
  # Handles webhook verification and payload parsing for WhatsApp Cloud API
  #
  # ## Webhook Verification
  #
  # When you configure a webhook in Meta's dashboard, they will send a GET request
  # to verify your endpoint. You need to handle this verification request.
  #
  # ## Webhook Payloads
  #
  # After verification, Meta will send POST requests with message payloads.
  # These payloads contain information about incoming messages, message status updates, etc.
  #
  # ## Usage Example with Kemal
  #
  # ```
  # # Webhook verification endpoint
  # get "/webhook" do |env|
  #   mode = env.params.query["hub.mode"]
  #   token = env.params.query["hub.verify_token"]
  #   challenge = env.params.query["hub.challenge"]
  #
  #   if WhatsApp::Webhook.verify?(mode, token, "your_verify_token")
  #     challenge
  #   else
  #     halt 403, "Forbidden"
  #   end
  # end
  #
  # # Webhook payload endpoint
  # post "/webhook" do |env|
  #   body = env.request.body.not_nil!.gets_to_end
  #
  #   if WhatsApp::Webhook.valid_signature?(env.request.headers, body, "your_app_secret")
  #     payload = WhatsApp::Webhook.parse_payload(body)
  #
  #     # Handle messages
  #     payload.each_entry do |entry|
  #       entry.each_change do |change|
  #         change.each_message do |message|
  #           # Process message
  #           puts "Message from #{message.from}: #{message.text}"
  #         end
  #       end
  #     end
  #
  #     {status: "ok"}.to_json
  #   else
  #     halt 403, "Invalid signature"
  #   end
  # end
  # ```
  module Webhook
    # Verify a webhook verification request from Meta
    #
    # @param mode [String?] The hub.mode parameter from the request
    # @param token [String?] The hub.verify_token parameter from the request
    # @param expected_token [String] Your configured verify token
    # @return [Bool] true if the verification is valid
    def self.verify?(mode : String?, token : String?, expected_token : String) : Bool
      mode == "subscribe" && token == expected_token
    end

    # Verify the X-Hub-Signature-256 header from a webhook payload
    #
    # Meta signs webhook payloads with HMAC-SHA256 using your app secret.
    # This verifies that the payload actually came from Meta.
    #
    # @param headers [HTTP::Headers] The request headers
    # @param body [String] The raw request body
    # @param app_secret [String] Your app secret from Meta dashboard
    # @return [Bool] true if the signature is valid
    def self.valid_signature?(headers : HTTP::Headers, body : String, app_secret : String) : Bool
      signature_header = headers["X-Hub-Signature-256"]?
      return false unless signature_header

      # Extract signature from "sha256=<signature>" format
      unless signature_header.starts_with?("sha256=")
        return false
      end

      provided_signature = signature_header[7..-1]

      # Calculate expected signature
      hmac = OpenSSL::HMAC.hexdigest(:sha256, app_secret, body)
      expected_signature = String.new(hmac.to_slice)

      # Use constant-time comparison to prevent timing attacks
      cryptographic_compare(provided_signature, expected_signature)
    end

    # Parse a webhook payload from Meta
    #
    # @param body [String] The raw JSON payload body
    # @return [Payload] The parsed webhook payload
    def self.parse_payload(body : String) : Payload
      Payload.from_json(body)
    end

    # Constant-time string comparison to prevent timing attacks
    private def self.cryptographic_compare(a : String, b : String) : Bool
      return false unless a.bytesize == b.bytesize

      result = 0_u8
      a_bytes = a.to_slice
      b_bytes = b.to_slice

      a_bytes.size.times do |i|
        result |= a_bytes[i] ^ b_bytes[i]
      end

      result == 0
    end

    # Represents a webhook payload from Meta
    class Payload
      include JSON::Serializable

      getter entry : Array(Entry)

      # Iterate over each entry in the payload
      def each_entry(& : Entry ->)
        @entry.each do |entry|
          yield entry
        end
      end

      # Check if this is a webhook verification request (for reference)
      def verification? : Bool
        false # Webhook payloads don't have this field
      end
    end

    # Represents an entry in the webhook payload
    #
    # An entry can contain multiple changes (messages, status updates, etc.)
    class Entry
      include JSON::Serializable

      getter id : String
      getter changes : Array(Change)

      # Iterate over each change in this entry
      def each_change(& : Change ->)
        @changes.each do |change|
          yield change
        end
      end
    end

    # Represents a change in an entry
    #
    # Changes can be of different types (messages, message status, etc.)
    class Change
      include JSON::Serializable

      getter value : ChangeValue

      # Iterate over each message in this change (if any)
      def each_message(& : Message ->)
        if @value.is_a?(MessagesValue)
          @value.as(MessagesValue).each_message do |message|
            yield message
          end
        end
      end

      # Check if this change contains messages
      def has_messages? : Bool
        @value.is_a?(MessagesValue)
      end

      # Get the messages value if this is a messages change
      def messages_value : MessagesValue?
        @value.as(MessagesValue) if @value.is_a?(MessagesValue)
      end
    end

    # Base class for change values
    abstract class ChangeValue
      include JSON::Serializable

      use_json_discriminator "field", {
        "messages": MessagesValue,
      }
    end

    # Represents a messages change value
    #
    # This contains the actual message data from WhatsApp
    class MessagesValue < ChangeValue
      include JSON::Serializable

      @[JSON::Field(key: "messages")]
      property messages : Array(Message)

      getter messaging_product : String

      # Iterate over each message
      def each_message(& : Message ->)
        @messages.each do |message|
          yield message
        end
      end
    end

    # Represents a message from WhatsApp
    #
    # Contains the message content and metadata
    class Message
      include JSON::Serializable

      # Get the message ID
      getter id : String

      # Get the phone number who sent the message
      def from : String
        @from
      end

      # Get the phone number who received the message (your bot)
      getter to : String

      # Get the timestamp
      getter timestamp : Time

      # Get the message type (text, image, audio, etc.)
      getter type : String

      # Get the text content if this is a text message
      def text : String?
        @text.try(&.as(Text)).try(&.body)
      end

      # Check if this is a text message
      def text? : Bool
        @type == "text"
      end

      # Get the from phone number
      @[JSON::Field(key: "from")]
      getter from : String

      # Text message specific data
      @[JSON::Field(key: "text")]
      getter text : Text?

      # Text message structure
      class Text
        include JSON::Serializable

        getter body : String
      end
    end
  end
end
