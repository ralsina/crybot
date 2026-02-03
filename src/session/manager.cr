require "json"
require "file_utils"
require "../config/loader"
require "../providers/base"

module Crybot
  module Session
    # Callback type for when messages are saved
    alias SaveCallback = Proc(String, Array(Providers::Message), Nil)

    class Manager
      @sessions_dir : Path
      @cache : Hash(String, Array(Providers::Message))
      @save_callbacks = Array(SaveCallback).new

      def initialize
        @sessions_dir = Config::Loader.sessions_dir
        @cache = {} of String => Array(Providers::Message)
      end

      def self.instance : Manager
        @@instance ||= Manager.new
      end

      def on_save(&callback : SaveCallback) : Nil
        @save_callbacks << callback
      end

      def get_or_create(session_key : String) : Array(Providers::Message)
        # Sanitize the key for consistent cache/file storage
        sanitized_key = sanitize_key(session_key)

        # Check cache first
        if @cache.has_key?(sanitized_key)
          return @cache[sanitized_key]
        end

        # Load from file
        session_file = @sessions_dir / "#{sanitized_key}.jsonl"

        messages = [] of Providers::Message

        if File.exists?(session_file)
          File.each_line(session_file) do |line|
            begin
              json = JSON.parse(line)
              msg = Providers::Message.new(
                role: json["role"].as_s,
                content: json["content"]?.try(&.as_s),
                tool_call_id: json["tool_call_id"]?.try(&.as_s),
                name: json["name"]?.try(&.as_s),
              )

              # Parse tool_calls if present
              tool_calls_value = json["tool_calls"]?
              if tool_calls_value && tool_calls_value.as_a?
                tool_calls = [] of Providers::ToolCall
                tool_calls_value.as_a.each do |tool_call|
                  id = tool_call["id"].as_s
                  name = tool_call["name"].as_s
                  args_str = tool_call["arguments"].as_s
                  arguments = JSON.parse(args_str).as_h

                  args_hash = {} of String => JSON::Any
                  arguments.each do |k, v|
                    args_hash[k] = v
                  end

                  tool_calls << Providers::ToolCall.new(
                    id: id,
                    name: name,
                    arguments: args_hash,
                  )
                end
                msg = Providers::Message.new(
                  role: msg.role,
                  content: msg.content,
                  tool_calls: tool_calls,
                  tool_call_id: msg.tool_call_id,
                  name: msg.name,
                )
              end

              messages << msg
            rescue e : Exception
              # Skip invalid lines
            end
          end
        end

        @cache[sanitized_key] = messages
        messages
      end

      def save(session_key : String, messages : Array(Providers::Message)) : Nil
        sanitized_key = sanitize_key(session_key)
        session_file = @sessions_dir / "#{sanitized_key}.jsonl"

        File.open(session_file, "w") do |file|
          messages.each do |msg|
            json_hash = Hash(String, JSON::Any).new
            json_hash["role"] = JSON::Any.new(msg.role)

            content = msg.content
            json_hash["content"] = JSON::Any.new(content) if content

            tool_call_id = msg.tool_call_id
            json_hash["tool_call_id"] = JSON::Any.new(tool_call_id) if tool_call_id

            name = msg.name
            json_hash["name"] = JSON::Any.new(name) if name

            calls = msg.tool_calls
            if calls && !calls.empty?
              tool_calls_array = calls.map do |tool_call|
                JSON::Any.new({
                  "id"        => JSON::Any.new(tool_call.id),
                  "name"      => JSON::Any.new(tool_call.name),
                  "arguments" => JSON::Any.new(tool_call.arguments.to_json),
                })
              end
              json_hash["tool_calls"] = JSON::Any.new(tool_calls_array)
            end

            file.puts json_hash.to_json
          end
        end

        @cache[sanitized_key] = messages

        # Trigger save callbacks
        @save_callbacks.each do |callback|
          begin
            callback.call(session_key, messages)
          rescue e : Exception
            # Don't let one callback failure break others
          end
        end
      end

      def delete(session_key : String) : Nil
        sanitized_key = sanitize_key(session_key)
        session_file = @sessions_dir / "#{sanitized_key}.jsonl"

        File.delete(session_file) if File.exists?(session_file)
        @cache.delete(sanitized_key)
      end

      def list_sessions : Array(String)
        return [] of String unless Dir.exists?(@sessions_dir)

        Dir.children(@sessions_dir).map do |filename|
          filename.sub(/\.jsonl$/, "")
        end
      end

      private def sanitize_key(key : String) : String
        # Replace special characters with underscores
        key.gsub(/[^a-zA-Z0-9_-]/, "_")
      end
    end

    @@instance : Manager?
  end
end
