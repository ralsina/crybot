require "log"
require "./openai_base"
require "json"

module Crybot
  module Providers
    # Google Gemini provider - https://ai.google.dev/gemini-api/docs
    # Uses OpenAI-compatible API endpoint (supported by Gemini)
    class GeminiProvider < OpenAICompatible
      API_BASE      = "https://generativelanguage.googleapis.com/v1beta/openai"
      DEFAULT_MODEL = "gemini-2.5-flash"

      def initialize(api_key : String, default_model : String = DEFAULT_MODEL)
        super(api_key, default_model, API_BASE)
      end

      # Override chat to extract Gemini's suggested retry delay from error responses
      def chat(messages : Array(Message), tools : Array(ToolDef)?, model : String?) : Response
        request_body = build_request_body(messages, tools, model)
        headers = build_headers

        max_retries = 5
        base_delay = 1.0 # seconds

        max_retries.times do |attempt|
          response = HTTP::Client.post(endpoint_url, headers, request_body.to_json)

          if response.success?
            return parse_response(response.body)
          end

          status = response.status_code
          if status == 429 || status >= 500
            if attempt < max_retries - 1
              # Try to extract suggested retry delay from Gemini error response
              suggested_delay = extract_retry_delay(response.body)

              # Use exponential backoff, but respect Gemini's suggested delay if present
              calculated_delay = base_delay * (2 ** attempt) + (rand * 0.5)
              delay = suggested_delay ? [calculated_delay, suggested_delay].max : calculated_delay

              # Check if this is a quota exceeded error (daily limit)
              if response.body.includes?("quota") || response.body.includes?("Quota exceeded")
                Log.warn { "[Gemini] Daily quota exceeded (20 requests/day for free tier)." }
                Log.warn { "[Gemini] Wait ~24 hours or upgrade to a paid plan for more requests." }
                Log.info { "[Gemini] Retrying in #{delay.round(2)}s (attempt #{attempt + 1}/#{max_retries})" }
              else
                Log.warn { "[Gemini] Rate limited (#{status}), retrying in #{delay.round(2)}s (attempt #{attempt + 1}/#{max_retries})" }
              end

              sleep delay.seconds
              next
            end
          end

          raise "API request failed: #{status} - #{response.body}"
        end

        raise "Max retries exceeded"
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def extract_retry_delay(error_body : String) : Float64?
        begin
          error_json = JSON.parse(error_body)

          # Check for Gemini's retryInfo in details array
          error_value = error_json["error"]?
          if error_value
            details_value = error_value["details"]?
            if details_value && details_value.as_a?
              details_value.as_a.each do |detail|
                type_value = detail["@type"]?
                if type_value && type_value.as_s == "type.googleapis.com/google.rpc.RetryInfo"
                  retry_delay_value = detail["retryDelay"]?
                  if retry_delay_value
                    retry_delay_str = retry_delay_value.as_s
                    # Parse "7s" format to seconds
                    if retry_delay_str.ends_with?("s")
                      return retry_delay_str.chomp("s").to_f64
                    end
                  end
                end
              end
            end

            # Also check error message for "Please retry in X.Xs" pattern
            message_value = error_value["message"]?
            if message_value
              message = message_value.as_s
              if match = message.match(/Please retry in ([\d.]+)s/)
                return match[1].to_f64
              end
            end
          end
        rescue
          # If parsing fails, return nil
        end

        nil
      end

      private def build_headers : HTTP::Headers
        HTTP::Headers{
          "Content-Type"  => "application/json",
          "Authorization" => "Bearer #{@api_key}",
        }
      end

      # Override to filter out 'name' field from tool messages for Gemini compatibility
      private def build_request_body(messages : Array(Message), tools : Array(ToolDef)?, model : String?) : Hash(String, JSON::Any)
        # Convert messages, omitting 'name' field for tool messages
        converted_messages = messages.map do |msg|
          msg_hash = msg.to_h
          # For tool role messages, remove the 'name' field if present
          # Gemini expects tool results without the name field
          if msg.role == "tool" && msg_hash.has_key?("name")
            msg_hash.delete("name")
          end
          msg_hash
        end

        body = {
          "model"    => JSON::Any.new(model || @default_model),
          "messages" => JSON::Any.new(converted_messages.map { |hash| JSON::Any.new(hash) }),
        }

        # Add tools if present
        unless tools.nil? || tools.empty?
          body["tools"] = JSON::Any.new(tools.map(&.to_h).map { |hash| JSON::Any.new(hash) })
        end

        body
      end
    end
  end
end
