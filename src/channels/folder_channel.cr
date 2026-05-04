require "./channel"
require "../agent/skill_manager"
require "log"
require "file_utils"

module Crybot
  module Channels
    # FolderChannel - saves messages to local files
    class FolderChannel < Channel
      @skill_manager : SkillManager
      @base_dir : Path

      def initialize(@skill_manager : SkillManager, @base_dir : Path = Path.home / ".crybot" / "folder")
        # Ensure the base directory exists
        Dir.mkdir_p(@base_dir) unless Dir.exists?(@base_dir)
      end

      def name : String
        "folder"
      end

      def start : Nil
        Log.info { "[FolderChannel] Starting folder channel" }
        Log.info { "[FolderChannel] Saving messages to: #{@base_dir}" }
      end

      def stop : Nil
        Log.info { "[FolderChannel] Stopping folder channel" }
      end

      def send_message(message : ChannelMessage) : Nil
        content = message.content_for_channel(self)

        Log.info { "[FolderChannel] send_message called: chat_id=#{message.chat_id}, content_size=#{content.size}" }

        # Create a filename based on timestamp and chat_id
        timestamp = Time.utc.to_s("%Y%m%d_%H%M%S")
        safe_chat_id = message.chat_id.gsub(/[^a-zA-Z0-9_-]/, "_")
        filename = "#{timestamp}_#{safe_chat_id}.md"

        # Create full file path
        filepath = @base_dir / filename

        Log.info { "[FolderChannel] Writing to: #{filepath}" }

        # Save content to file
        File.write(filepath, content)

        Log.info { "[FolderChannel] Saved message to: #{filepath}" }
        puts "[FolderChannel] 📁 Saved: #{filepath}"

        # Also save a debug version with full message metadata
        if ENV["DEBUG_FOLDER_CHANNEL"]?
          debug_filepath = @base_dir / "#{filename}.debug.json"
          debug_content = {
            timestamp:        Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ"),
            chat_id:          message.chat_id,
            role:             message.role,
            format:           message.format,
            content:          content,
            metadata:         message.metadata,
            raw_content_size: message.content.try(&.size) || 0,
          }.to_json
          File.write(debug_filepath, debug_content)
          Log.debug { "[FolderChannel] Debug metadata saved to: #{debug_filepath}" }
        end
      rescue e : Exception
        Log.error(exception: e) { "[FolderChannel] Exception: #{e.message}, #{e.backtrace.join("\n")}" }
      end

      def session_key(chat_id : String) : String
        # Folder uses a simple flat structure
        "folder_#{chat_id}"
      end

      def supports_markdown? : Bool
        false # We save the content as-is
      end

      def preferred_format : ChannelMessage::MessageFormat
        ChannelMessage::MessageFormat::Markdown
      end
    end
  end
end
