require "json"
require "file_utils"
require "../config/loader"
require "../providers/base"
require "./metadata"

module Crybot
  module Session
    # Callback type for when messages are saved
    alias SaveCallback = Proc(String, Array(Providers::Message), Nil)

    class Manager
      @sessions_dir : Path
      @cache : Hash(String, Array(Providers::Message))
      @metadata_cache : Hash(String, Metadata)
      @save_callbacks = Array(SaveCallback).new
      @provider_name : String?

      def initialize
        @sessions_dir = Config::Loader.sessions_dir
        @cache = {} of String => Array(Providers::Message)
        @metadata_cache = {} of String => Metadata
      end

      def provider=(provider_name : String) : Nil
        @provider_name = provider_name
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

        # Sanitize messages based on provider
        messages = sanitize_messages_for_provider(messages)

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

        # Update metadata with last user/assistant message
        last_content_message = messages.reverse.find { |msg| msg.content && msg.role != "system" }
        if last_content_message
          content = last_content_message.content
          if content
            update_last_message(session_key, content)
          end
        end

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
        metadata_file = @sessions_dir / "#{sanitized_key}.meta.json"

        File.delete(session_file) if File.exists?(session_file)
        File.delete(metadata_file) if File.exists?(metadata_file)
        @cache.delete(sanitized_key)
        @metadata_cache.delete(sanitized_key)
      end

      # Trim a session to keep only messages after a certain time
      def trim_session(session_key : String, cutoff_time : Time) : Nil
        # For scheduled tasks, we clear the session entirely when memory expiration is set
        # This ensures the task starts fresh each time
        save(session_key, [] of Providers::Message)
      end

      def list_sessions : Array(String)
        return [] of String unless Dir.exists?(@sessions_dir)

        Dir.children(@sessions_dir)
          .select(&.ends_with?(".jsonl"))
          .map(&.sub(/\.jsonl$/, ""))
      end

      # Get metadata for a session, creating default if it doesn't exist
      def get_metadata(session_key : String) : Metadata
        sanitized_key = sanitize_key(session_key)

        # Check cache first
        if @metadata_cache.has_key?(sanitized_key)
          return @metadata_cache[sanitized_key]
        end

        metadata_file = @sessions_dir / "#{sanitized_key}.meta.json"

        if File.exists?(metadata_file)
          begin
            metadata = Metadata.from_json(File.read(metadata_file))
            # Ensure session_type is set (for backward compatibility with old metadata files)
            if metadata.session_type == "unknown"
              metadata.session_type = detect_session_type(session_key)
              save_metadata(session_key, metadata)
            end
            @metadata_cache[sanitized_key] = metadata
            return metadata
          rescue e : Exception
            # If metadata is corrupted, create new default
          end
        end

        # Create default metadata with detected session type
        session_type = detect_session_type(session_key)
        metadata = Metadata.new(session_type: session_type)
        @metadata_cache[sanitized_key] = metadata
        save_metadata(session_key, metadata)
        metadata
      end

      # Detect session type from session key
      private def detect_session_type(session_key : String) : String
        case session_key
        when /^web_/      then "web"
        when /^telegram:/ then "telegram"
        when /^repl_/     then "repl"
        when /^repl$/     then "repl"
        when /^voice$/    then "voice"
        when /^whatsapp:/ then "whatsapp"
        when /^slack:/    then "slack"
        when /^cli$/      then "cli"
        else                   "unknown"
        end
      end

      # Save metadata for a session
      def save_metadata(session_key : String, metadata : Metadata) : Nil
        sanitized_key = sanitize_key(session_key)
        metadata_file = @sessions_dir / "#{sanitized_key}.meta.json"

        File.write(metadata_file, metadata.to_pretty_json)
        @metadata_cache[sanitized_key] = metadata
      end

      # Update the last message in metadata when a new user message is sent
      def update_last_message(session_key : String, content : String) : Nil
        metadata = get_metadata(session_key)
        metadata.update_last_message(content)
        save_metadata(session_key, metadata)
      end

      # Update the description (can be called by agent/LLM)
      def update_description(session_key : String, description : String) : Nil
        metadata = get_metadata(session_key)
        metadata.update_description(description)
        save_metadata(session_key, metadata)
      end

      # Update the title
      def update_title(session_key : String, title : String) : Nil
        metadata = get_metadata(session_key)
        metadata.update_title(title)
        save_metadata(session_key, metadata)
      end

      # Get all sessions with their metadata
      def list_sessions_with_metadata : Array(Hash(String, JSON::Any))
        sessions = list_sessions

        sessions.map do |session_key|
          metadata = get_metadata(session_key)
          {
            "id"           => JSON::Any.new(session_key),
            "title"        => JSON::Any.new(metadata.title),
            "description"  => JSON::Any.new(metadata.description),
            "last_message" => JSON::Any.new(metadata.last_message),
            "updated_at"   => JSON::Any.new(metadata.updated_at),
            "session_type" => JSON::Any.new(metadata.session_type),
          }
        end
      end

      private def sanitize_key(key : String) : String
        # Replace special characters with underscores
        key.gsub(/[^a-zA-Z0-9_-]/, "_")
      end

      # Sanitize messages based on the current provider's requirements
      # This allows switching between providers with different message format requirements
      private def sanitize_messages_for_provider(messages : Array(Providers::Message)) : Array(Providers::Message)
        provider = @provider_name

        messages.map do |msg|
          case provider
          when "gemini"
            # Gemini doesn't accept 'name' field in tool result messages
            if msg.role == "tool" && msg.name
              Providers::Message.new(
                role: msg.role,
                content: msg.content,
                tool_calls: msg.tool_calls,
                tool_call_id: msg.tool_call_id,
                name: nil, # Strip name for Gemini
              )
            else
              msg
            end
          else
            # Other providers accept the standard format
            msg
          end
        end
      end
    end

    @@instance : Manager?
  end
end
