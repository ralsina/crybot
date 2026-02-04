require "./channel"

module Crybot
  module Channels
    # Voice channel - handles voice-activated interactions
    # Messages are spoken aloud via TTS
    class VoiceChannel < Channel
      @tts_command : String
      @push_to_talk_file : Path

      def initialize(@tts_command : String = "piper-tts", @push_to_talk_file : Path = Path["/tmp/voice_ptt"])
      end

      def name : String
        "voice"
      end

      def start : Nil
        # Voice listener is started separately by VoiceFeature
        # This is a no-op for the channel adapter
      end

      def stop : Nil
        # Voice listener is stopped separately
      end

      def send_message(message : ChannelMessage) : Nil
        # Get content in plain format for TTS
        content = message.content_for_channel(self)

        # Convert to plain text for speaking
        plain_content = strip_formatting(content)

        # Speak the message
        speak(plain_content)
      end

      def session_key(chat_id : String) : String
        # Voice uses a single shared session
        "voice"
      end

      def preferred_format : ChannelMessage::MessageFormat
        ChannelMessage::MessageFormat::Plain
      end

      def max_message_length : Int32
        1000 # TTS has limits on what can be spoken reasonably
      end

      private def speak(text : String) : Nil
        # Use piper-tts or festival for text-to-speech
        # This is a simplified implementation
        temp_file = "/tmp/voice_response.wav"

        # Use piper-tts if available, otherwise festival
        if @tts_command == "piper-tts"
          Process.run("piper-tts", ["--model", "/usr/share/piper-voices/en/en_GB/alan/medium/en_GB-alan-medium.onnx", "--output", temp_file, text]) do
            # Optional: play the audio file
            if File.exists?(temp_file)
              Process.run("aplay", [temp_file])
              File.delete(temp_file)
            end
          end
        else
          # Fallback to festival
          Process.run("echo", [text, "|", "festival", "--tts"])
        end
      rescue e : Exception
        puts "[VoiceChannel] TTS error: #{e.message}"
      end

      private def strip_formatting(text : String) : String
        # Remove markdown/code formatting for speech
        text
          .gsub(/\*\*(.*?)\*\*/, "\\1")         # Bold
          .gsub(/\*(.*?)\*/, "\\1")             # Italic
          .gsub(/`(.*?)`/, "\\1")               # Inline code
          .gsub(/```[\s\S]*?```/, "")           # Code blocks
          .gsub(/^#+\s/, "")                    # Headers
          .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1") # Links
          .strip
      end
    end
  end
end
