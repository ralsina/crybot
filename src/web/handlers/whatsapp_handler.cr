require "../../channels/whatsapp_channel"

module Crybot
  module Web
    module Handlers
      class WhatsAppHandler
        @whatsapp_channel : Channels::WhatsAppChannel?

        def initialize
        end

        # Set the WhatsApp channel reference (called by web feature)
        def channel=(channel : Channels::WhatsAppChannel) : Nil
          @whatsapp_channel = channel
        end

        # Handle webhook verification (GET request from Meta)
        def verify_webhook(env) : String
          mode = env.params.query["hub.mode"]?
          token = env.params.query["hub.verify_token"]?
          challenge = env.params.query["hub.challenge"]?

          if channel = @whatsapp_channel
            if channel.verify_webhook(mode, token)
              puts "[Web/WhatsApp] Webhook verified"
              return challenge || ""
            end
          end

          env.response.status_code = 403
          "Forbidden"
        end

        # Handle webhook payload (POST request from Meta)
        def handle_webhook(env) : String
          body = env.request.body.try(&.gets_to_end) || ""

          if channel = @whatsapp_channel
            # Verify signature
            if channel.valid_webhook_signature?(env.request.headers, body)
              puts "[Web/WhatsApp] Received webhook payload"

              # Process the webhook
              spawn do
                begin
                  channel.handle_webhook(body)
                rescue e : Exception
                  puts "[Web/WhatsApp] Error processing webhook: #{e.message}"
                  puts e.backtrace.join("\n") if ENV["DEBUG"]?
                end
              end

              return {status: "ok"}.to_json
            else
              puts "[Web/WhatsApp] Invalid webhook signature"
            end
          end

          env.response.status_code = 403
          {error: "Invalid signature"}.to_json
        end
      end
    end
  end
end
