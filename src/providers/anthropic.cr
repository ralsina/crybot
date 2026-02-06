require "http"
require "json"
require "./base"

module Crybot
  module Providers
    # Anthropic provider (Claude)
    class AnthropicProvider < LLMProvider
      API_BASE      = "https://api.anthropic.com/v1/messages"
      DEFAULT_MODEL = "claude-3-5-sonnet-20241022"

      def initialize(@api_key : String, @default_model : String = DEFAULT_MODEL)
      end

      def chat(messages : Array(Message), tools : Array(ToolDef)?, model : String?) : Response
        request_body = build_request_body(messages, tools, model)

        headers = HTTP::Headers{
          "Content-Type"      => "application/json",
          "x-api-key"         => @api_key,
          "anthropic-version" => "2023-06-01",
        }

        # Exponential backoff for rate limits (429) and server errors (5xx)
        max_retries = 5
        base_delay = 1.0  # seconds

        max_retries.times do |attempt|
          response = HTTP::Client.post(API_BASE, headers, request_body.to_json)

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
              puts "[Provider] Rate limited (#{status}), retrying in #{delay.round(2)}s (attempt #{attempt + 1}/#{max_retries})"
              sleep delay.seconds
              next
            end
          end

          # Other error or max retries exceeded
          raise "API request failed: #{status} - #{response.body}"
        end

        # Should not reach here, but compiler needs a return
        raise "Max retries exceeded"
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def build_request_body(messages : Array(Message), tools : Array(ToolDef)?, model : String?) : Hash(String, JSON::Any)
        # Convert OpenAI-style messages to Anthropic format
        system_message = nil
        user_messages = [] of Hash(String, JSON::Any)

        messages.each do |msg|
          case msg.role
          when "system"
            system_message = msg.content
          when "user"
            user_messages << {"role" => JSON::Any.new("user"), "content" => JSON::Any.new(msg.content || "")}
          when "assistant"
            content = build_assistant_content(msg)
            user_messages << {"role" => JSON::Any.new("assistant"), "content" => content}
          when "tool"
            # Anthropic uses tool_result type
            tool_result_array = [
              JSON::Any.new({
                "type"        => JSON::Any.new("tool_result"),
                "tool_use_id" => JSON::Any.new(msg.tool_call_id || ""),
                "content"     => JSON::Any.new(msg.content || ""),
              }),
            ]
            user_messages << {
              "role"    => JSON::Any.new("user"),
              "content" => JSON::Any.new(tool_result_array),
            }
          end
        end

        body = {
          "model"      => JSON::Any.new(model || @default_model),
          "messages"   => JSON::Any.new(user_messages.map { |hash| JSON::Any.new(hash) }),
          "max_tokens" => JSON::Any.new(8192),
        }

        if system_message
          body["system"] = JSON::Any.new(system_message)
        end

        # Add tools if present (Anthropic format)
        unless tools.nil? || tools.empty?
          body["tools"] = JSON::Any.new(tools.map { |tool| convert_tool_to_anthropic(tool) }.map { |tool_hash| JSON::Any.new(tool_hash) })
        end

        body
      end

      private def build_assistant_content(msg : Message) : JSON::Any
        tool_calls = msg.tool_calls
        if tool_calls && !tool_calls.empty?
          # Build content array with tool_use blocks
          content_array = tool_calls.map do |tool_call|
            JSON::Any.new({
              "type"  => JSON::Any.new("tool_use"),
              "id"    => JSON::Any.new(tool_call.id),
              "name"  => JSON::Any.new(tool_call.name),
              "input" => JSON::Any.new(tool_call.arguments),
            })
          end

          # Add text content if present
          content = msg.content
          if content && !content.empty?
            content_array.unshift(JSON::Any.new({
              "type" => JSON::Any.new("text"),
              "text" => JSON::Any.new(content),
            }))
          end

          JSON::Any.new(content_array)
        else
          JSON::Any.new(msg.content || "")
        end
      end

      private def convert_tool_to_anthropic(tool : ToolDef) : Hash(String, JSON::Any)
        {
          "name"         => JSON::Any.new(tool.name),
          "description"  => JSON::Any.new(tool.description),
          "input_schema" => JSON::Any.new(tool.parameters),
        }
      end

      private def parse_response(body : String) : Response
        json = JSON.parse(body)

        content = nil
        tool_calls = nil
        usage = nil
        finish_reason = nil

        # Parse content blocks
        content_blocks = json["content"]?
        if content_blocks && content_blocks.as_a?
          text_parts = [] of String
          tool_calls_array = [] of ToolCall

          content_blocks.as_a.each do |block|
            type = block["type"]?.try(&.as_s)

            case type
            when "text"
              text_parts << block["text"].as_s
            when "tool_use"
              id = block["id"].as_s
              name = block["name"].as_s
              input = block["input"].as_h

              # Convert to Hash(String, JSON::Any)
              args_hash = {} of String => JSON::Any
              input.each { |k, v| args_hash[k] = v }

              tool_calls_array << ToolCall.new(
                id: id,
                name: name,
                arguments: args_hash,
              )
            end
          end

          content = text_parts.join("\n") unless text_parts.empty?
          tool_calls = tool_calls_array unless tool_calls_array.empty?
        end

        # Parse usage
        usage_value = json["usage"]?
        if usage_value
          usage = Usage.new(
            prompt_tokens: usage_value["input_tokens"].as_i.to_i32,
            completion_tokens: usage_value["output_tokens"].as_i.to_i32,
            total_tokens: (usage_value["input_tokens"].as_i + usage_value["output_tokens"].as_i).to_i32,
          )
        end

        # Parse stop_reason (Anthropic uses stop_reason instead of finish_reason)
        stop_reason = json["stop_reason"]?.try(&.as_s)
        finish_reason = map_stop_reason(stop_reason) if stop_reason

        Response.new(content: content, tool_calls: tool_calls, usage: usage, finish_reason: finish_reason)
      end

      private def map_stop_reason(reason : String) : String
        case reason
        when "end_turn"      then "stop"
        when "max_tokens"    then "length"
        when "tool_use"      then "tool_calls"
        when "stop_sequence" then "stop"
        else                      reason
        end
      end
    end
  end
end
