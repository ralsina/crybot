require "http"
require "json"
require "openssl"

module WhatsApp
  # Client for interacting with the WhatsApp Cloud API
  #
  # ## Configuration
  #
  # You need to get credentials from Meta's WhatsApp Cloud API:
  # 1. Create a Meta developer account: https://developers.facebook.com/
  # 2. Create a WhatsApp Business App
  # 3. Get your Phone Number ID and Access Token from the App Dashboard
  #
  # ## Basic Usage
  #
  # ```
  # client = WhatsApp::Client.new(
  #   phone_number_id: "123456789",
  #   access_token: "your_access_token"
  # )
  #
  # # Send a text message
  # client.send_text(
  #   to: "15551234567",
  #   text: "Hello from WhatsApp!"
  # )
  #
  # # Send a template message (required for first message to a user)
  # client.send_template(
  #   to: "15551234567",
  #   template_name: "hello_world",
  #   language_code: "en_US"
  # )
  # ```
  class Client
    private BASE_URL = "https://graph.facebook.com"

    getter phone_number_id : String
    getter access_token : String
    getter api_version : String

    def initialize(@phone_number_id : String, @access_token : String, @api_version : String = "v18.0")
    end

    # Send a text message to a WhatsApp user
    #
    # NOTE: The first message to a user must be a template message.
    # After the user replies, you can send text messages.
    #
    # @param to [String] The recipient's phone number in international format (e.g., "15551234567")
    # @param text [String] The message content
    # @return [Hash] The API response
    def send_text(to : String, text : String) : Hash(String, JSON::Any)
      body = Hash(String, JSON::Any).new
      body["messaging_product"] = JSON::Any.new("whatsapp")
      body["to"] = JSON::Any.new(to)
      body["type"] = JSON::Any.new("text")

      text_obj = Hash(String, JSON::Any).new
      text_obj["body"] = JSON::Any.new(text)
      body["text"] = JSON::Any.new(text_obj)

      post_message(body)
    end

    # Send a template message to a WhatsApp user
    #
    # Template messages are required for the first message to a user.
    # Templates must be pre-approved in your WhatsApp Business App.
    #
    # @param to [String] The recipient's phone number
    # @param template_name [String] The name of the template from your WhatsApp Business App
    # @param language_code [String] The language code (e.g., "en_US")
    # @param components [Array(Hash)?] Optional template components
    # @return [Hash] The API response
    def send_template(to : String, template_name : String, language_code : String = "en_US", components : Array(Hash)? = nil) : Hash(String, JSON::Any)
      body = Hash(String, JSON::Any).new
      body["messaging_product"] = JSON::Any.new("whatsapp")
      body["to"] = JSON::Any.new(to)
      body["type"] = JSON::Any.new("template")

      template_obj = Hash(String, JSON::Any).new
      template_obj["name"] = JSON::Any.new(template_name)

      language_obj = Hash(String, JSON::Any).new
      language_obj["code"] = JSON::Any.new(language_code)
      template_obj["language"] = JSON::Any.new(language_obj)

      if components
        # Convert Array(Hash) to Array(JSON::Any)
        components_any = components.map do |comp|
          JSON::Any.new(comp)
        end
        template_obj["components"] = JSON::Any.new(components_any)
      end

      body["template"] = JSON::Any.new(template_obj)

      post_message(body)
    end

    # Mark a message as read
    #
    # @param message_id [String] The ID of the message to mark as read
    # @return [Hash] The API response
    def mark_as_read(message_id : String) : Hash(String, JSON::Any)
      # For marking as read, we POST to the messages endpoint
      headers = headers_with_auth
      url = "#{BASE_URL}/#{@api_version}/#{message_id}"

      body = Hash(String, JSON::Any).new
      body["status"] = JSON::Any.new("read")

      response = HTTP::Client.post(
        url,
        headers: headers,
        body: body.to_json
      )

      parse_response(response)
    end

    # Get the URL for the webhook configuration
    def webhook_url : String
      "#{BASE_URL}/#{@api_version}/#{@phone_number_id}"
    end

    # Get the URL for posting messages
    private def message_url : String
      "#{BASE_URL}/#{@api_version}/#{@phone_number_id}/messages"
    end

    # Post a message to the WhatsApp API
    private def post_message(body : Hash) : Hash(String, JSON::Any)
      headers = headers_with_auth
      url = message_url

      response = HTTP::Client.post(
        url,
        headers: headers,
        body: body.to_json
      )

      parse_response(response)
    end

    # Parse the API response
    private def parse_response(response : HTTP::Client::Response) : Hash(String, JSON::Any)
      body = response.body

      if response.success?
        hash = JSON.parse(body).as_h
        # Check for WhatsApp API errors
        if hash["error"]?
          raise Exception.new("WhatsApp API error: #{hash["error"]}")
        end
        hash
      else
        raise Exception.new("HTTP #{response.status_code}: #{body}")
      end
    end

    # Build headers with authentication
    private def headers_with_auth : HTTP::Headers
      HTTP::Headers{
        "Authorization" => "Bearer #{@access_token}",
        "Content-Type"  => "application/json",
      }
    end
  end
end
