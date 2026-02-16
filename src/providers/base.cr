require "log"

module Crybot
  module Providers
    Log = ::Log.for("crybot.providers")

    struct Message
      property role : String # "system", "user", "assistant", "tool"
      property content : String?
      property tool_calls : Array(ToolCall)?
      property tool_call_id : String?
      property name : String? # For tool messages

      def initialize(@role : String, @content : String? = nil, @tool_calls : Array(ToolCall)? = nil, @tool_call_id : String? = nil, @name : String? = nil)
      end

      def to_h : Hash(String, JSON::Any)
        hash = {"role" => JSON::Any.new(role)}
        hash["content"] = JSON::Any.new(content) unless content.nil?
        calls = tool_calls
        if calls && !calls.empty?
          hash["tool_calls"] = JSON::Any.new(calls.map(&.to_h).map { |item_hash| JSON::Any.new(item_hash) })
        end
        hash["tool_call_id"] = JSON::Any.new(tool_call_id) unless tool_call_id.nil?
        hash["name"] = JSON::Any.new(name) unless name.nil?
        hash
      end
    end

    struct ToolCall
      property id : String
      property name : String
      property arguments : Hash(String, JSON::Any)

      def initialize(@id : String, @name : String, @arguments : Hash(String, JSON::Any))
      end

      def to_h : Hash(String, JSON::Any)
        {
          "id"       => JSON::Any.new(id),
          "type"     => JSON::Any.new("function"),
          "function" => JSON::Any.new({
            "name"      => JSON::Any.new(name),
            "arguments" => JSON::Any.new(arguments.to_json),
          }),
        }
      end
    end

    struct Usage
      property prompt_tokens : Int32
      property completion_tokens : Int32
      property total_tokens : Int32

      def initialize(@prompt_tokens : Int32, @completion_tokens : Int32, @total_tokens : Int32)
      end
    end

    struct Response
      property content : String?
      property tool_calls : Array(ToolCall)?
      property usage : Usage?
      property finish_reason : String?

      def initialize(@content : String? = nil, @tool_calls : Array(ToolCall)? = nil, @usage : Usage? = nil, @finish_reason : String? = nil)
      end
    end

    struct ToolDef
      property name : String
      property description : String
      property parameters : Hash(String, JSON::Any)

      def initialize(@name : String, @description : String, @parameters : Hash(String, JSON::Any))
      end

      def to_h : Hash(String, JSON::Any)
        {
          "type"     => JSON::Any.new("function"),
          "function" => JSON::Any.new({
            "name"        => JSON::Any.new(name),
            "description" => JSON::Any.new(description),
            "parameters"  => JSON::Any.new(parameters),
          }),
        }
      end
    end

    abstract class LLMProvider
      abstract def chat(messages : Array(Message), tools : Array(ToolDef)?, model : String?, cancellation_token : ::Crybot::Agent::CancellationToken? = nil) : Response

      # Check for cancellation during request (optional override)
      def check_cancellation(token : ::Crybot::Agent::CancellationToken?) : Nil
        if token && token.cancelled?
          Log.info { "[Provider] Request cancelled by user" }
          raise "Request cancelled by user"
        end
      end
    end
  end
end
