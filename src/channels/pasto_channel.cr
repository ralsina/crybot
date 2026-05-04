require "./channel"
require "../agent/skill_manager"
require "log"

module Crybot
  module Channels
    # PastoChannel - posts messages to pasto pastebin service
    class PastoChannel < Channel
      @skill_manager : SkillManager

      # Store the most recent paste URL for access by other components
      @@last_url : String? = nil

      def self.last_url : String?
        @@last_url
      end

      def self.clear_url : Nil
        @@last_url = nil
      end

      def initialize(@skill_manager : SkillManager)
      end

      def name : String
        "pasto"
      end

      def start : Nil
        Log.info { "[PastoChannel] Starting pasto channel" }
      end

      def stop : Nil
        Log.info { "[PastoChannel] Stopping pasto channel" }
      end

      def send_message(message : ChannelMessage) : Nil
        content = message.content_for_channel(self)

        # Generate a title from metadata or use default
        title = message.metadata.try(&.["title"]?) || "Message from Crybot"
        date = Time.local.to_s("%Y-%m-%d")

        # Post to pasto using the skill
        post_to_pasto(content, title, date)
      end

      def session_key(chat_id : String) : String
        # Pasto doesn't really have sessions, but we use a shared one
        "pasto"
      end

      def supports_markdown? : Bool
        false # Pasto displays plain text
      end

      def preferred_format : ChannelMessage::MessageFormat
        ChannelMessage::MessageFormat::Plain
      end

      private def post_to_pasto(content : String, title : String, date : String) : Nil
        Log.info { "[PastoChannel] Posting to pasto: #{title}" }

        # Execute SSH command to post to pasto
        # Using basic Process.run since we're not in agent context
        begin
          # Build the full title with date
          full_title = "#{title} - #{date}"

          # Properly quote the title for the remote shell
          # We need to use shell quoting that will be preserved through SSH
          quoted_title = full_title.gsub("'", "'\\\\''")

          # Build the command as a string that SSH will execute
          # This ensures the title is treated as a single argument by the remote shell
          ssh_command = "paste -l markdown -t '#{quoted_title}'"

          Log.debug { "[PastoChannel] Running: ssh pasto1.ralsina.me -p 2222 #{ssh_command}" }

          # Run the command with content via stdin
          # We pass the command as a single string to SSH
          process = Process.new(
            "ssh",
            ["pasto1.ralsina.me", "-p", "2222", ssh_command],
            input: IO::Memory.new(content),
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )

          output = process.output.gets_to_end
          error = process.error.gets_to_end
          status = process.wait

          if status.success?
            # Pasto typically returns a URL in the output
            url = extract_url(output)
            if url
              @@last_url = url
              Log.info { "[PastoChannel] Successfully posted to pasto: #{url}" }
              puts "[PastoChannel] 📝 Paste created: #{url}"
            else
              Log.info { "[PastoChannel] Successfully posted to pasto (URL not found in output)" }
              Log.debug { "[PastoChannel] Output: #{output}" }
            end
          else
            Log.error { "[PastoChannel] Failed to post to pasto: #{error}" }
          end
        rescue e : Exception
          Log.error { "[PastoChannel] Exception posting to pasto: #{e.message}" }
        end
      end

      private def extract_url(output : String) : String?
        # Pasto typically returns URLs like:
        # https://pasto1.ralsina.me/p/abc123
        # or just: https://pasto1.ralsina.me/p/abc123
        # Try to extract the URL from the output
        if match = output.match(/https?:\/\/[^\s]+/i)
          match[0]
        else
          nil
        end
      end
    end
  end
end
