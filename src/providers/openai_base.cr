require "http"
require "json"
require "./base"
require "./async_http"
require "../agent/cancellation"

module Crybot
  module Providers
    # Base class for OpenAI-compatible API providers
    # All providers using the OpenAI chat completions format can inherit from this
    abstract class OpenAICompatible < LLMProvider
      @api_key : String
      @default_model : String
      @api_base : String

      def initialize(@api_key : String, @default_model : String, @api_base : String)
      end

      def chat(messages : Array(Message), tools : Array(ToolDef)?, model : String?, cancellation_token : ::Crybot::Agent::CancellationToken? = nil) : Response
        request_body = build_request_body(messages, tools, model)
        headers = build_headers

        # Exponential backoff for rate limits (429) and server errors (5xx)
        max_retries = 5
        base_delay = 1.0 # seconds

        max_retries.times do |attempt|
          # Check for cancellation before making request
          check_cancellation(cancellation_token)

          # Use async HTTP to allow cancellation during the request
          response = AsyncHTTP.post_with_cancellation(
            endpoint_url,
            headers,
            request_body.to_json,
            cancellation_token
          )

          # Success - return response
          if response.success?
            return parse_response(response.body)
          end

          # Check if it's a rate limit (429) or server error (5xx)
          status = response.status_code
          if status == 429 || status >= 500
            if attempt < max_retries - 1
              # Calculate exponential backoff with jitter
              delay = base_delay * (2 ** attempt) + (rand * 0.5)
              Log.warn { "Rate limited (#{status}), retrying in #{delay.round(2)}s (attempt #{attempt + 1}/#{max_retries})" }

              # Sleep in smaller increments to check for cancellation
              sleep_time = 0
              while sleep_time < delay
                sleep 0.1.seconds
                sleep_time += 0.1
                check_cancellation(cancellation_token)
              end

              next
            end
          end

          # Other error or max retries exceeded
          raise "API request failed: #{status} - #{response.body}"
        end

        # Should not reach here, but compiler needs a return
        raise "Max retries exceeded"
      end

      private def endpoint_url : String
        "#{@api_base}/chat/completions"
      end

      private def build_headers : HTTP::Headers
        HTTP::Headers{
          "Content-Type"  => "application/json",
          "Authorization" => "Bearer #{@api_key}",
        }
      end

      private def build_request_body(messages : Array(Message), tools : Array(ToolDef)?, model : String?) : Hash(String, JSON::Any)
        body = {
          "model"    => JSON::Any.new(model || @default_model),
          "messages" => JSON::Any.new(messages.map(&.to_h).map { |hash| JSON::Any.new(hash) }),
        }

        # Add tools if present
        if tools.nil? || tools.empty?
          Log.debug { "No tools being sent (tools nil or empty)" }
        else
          tools_array = tools.map(&.to_h).map { |hash| JSON::Any.new(hash) }
          body["tools"] = JSON::Any.new(tools_array)
          # Explicitly set tool_choice to auto (model decides when to use tools)
          body["tool_choice"] = JSON::Any.new("auto")
          Log.debug { "Sending #{tools.size} tools to API" }
        end

        body
      end

      private def parse_response(body : String) : Response
        json = JSON.parse(body)

        content = nil
        tool_calls = nil
        usage = nil
        finish_reason = nil

        choices_value = json["choices"]?
        if choices_value && choices_value.as_a?
          choice = choices_value.as_a[0]
          msg_value = choice["message"]?
          if msg_value
            msg = msg_value
            content_value = msg["content"]?
            content = content_value.as_s if content_value

            tool_calls_value = msg["tool_calls"]?
            if tool_calls_value && tool_calls_value.as_a?
              tool_calls = parse_tool_calls(tool_calls_value)
            end
          end

          finish_reason_value = choice["finish_reason"]?
          finish_reason = finish_reason_value.as_s if finish_reason_value
        end

        usage_value = json["usage"]?
        if usage_value
          usage_data = usage_value
          usage = Usage.new(
            prompt_tokens: usage_data["prompt_tokens"].as_i.to_i32,
            completion_tokens: usage_data["completion_tokens"].as_i.to_i32,
            total_tokens: usage_data["total_tokens"].as_i.to_i32,
          )
        end

        Response.new(content: content, tool_calls: tool_calls, usage: usage, finish_reason: finish_reason)
      end

      private def parse_tool_calls(calls : JSON::Any) : Array(ToolCall)
        result = [] of ToolCall

        calls.as_a.each do |call|
          id = call["id"].as_s
          func = call["function"]
          name = func["name"].as_s
          arguments_str = func["arguments"].as_s
          arguments = JSON.parse(arguments_str).as_h

          # Convert JSON::Any to proper Hash(String, JSON::Any)
          args_hash = {} of String => JSON::Any
          arguments.each do |k, v|
            args_hash[k] = v
          end

          result << ToolCall.new(
            id: id,
            name: name,
            arguments: args_hash,
          )
        end

        result
      end
    end
  end
end
