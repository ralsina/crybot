require "process"
require "file_utils"
require "../config/loader"
require "../providers/base"

module Crybot
  module Agent
    class VoiceListener
      @config : Config::ConfigFile
      @agent_loop : Loop
      @running : Bool = false

      # Configuration
      @wake_word : String = "crybot"
      @listen_duration : Int32 = 3   # seconds to listen for wake word
      @command_duration : Int32 = 10 # seconds to listen for command
      @whisper_path : String
      @audio_device : String?

      def initialize(@agent_loop : Loop)
        @config = Config::Loader.load

        # Get configuration from config file (voice section)
        if voice_config = @config.voice
          @wake_word = voice_config.wake_word || "crybot"
          @listen_duration = voice_config.listen_duration || 3
          @command_duration = voice_config.command_duration || 10
          @audio_device = voice_config.audio_device
        end

        # Find whisper.cpp binary
        @whisper_path = find_whisper_binary
      end

      def start : Nil
        @running = true

        puts "Voice listener started"
        puts "  Wake word: '#{@wake_word}'"
        puts "  Say '#{@wake_word}' followed by your command"
        puts "  Press Ctrl+C to stop"
        puts "---"

        while @running
          begin
            # Listen for wake word
            transcription = listen(@listen_duration)

            if transcription.empty?
              sleep 0.5.seconds
              next
            end

            puts "[Heard: #{transcription}]"

            # Check for wake word (case-insensitive, handle variations)
            if contains_wake_word?(transcription)
              puts "[Wake word detected!]"

              # Listen for command
              puts "Listening for command..."
              command = listen(@command_duration)

              if !command.empty?
                # Remove wake word from command if present
                clean_command = extract_command(command)
                puts "[Command: #{clean_command}]"

                # Send to agent
                process_command(clean_command)
              else
                puts "[No command detected]"
              end
            end
          rescue e : Exception
            puts "[Error: #{e.message}]"
            sleep 1.second
          end
        end
      end

      def stop : Nil
        @running = false
        puts "Voice listener stopped"
      end

      private def listen(duration : Int32) : String
        temp_audio = File.join(Dir.tempdir, "crybot_listen_#{Process.pid}.wav")

        begin
          # Record audio
          record_audio(temp_audio, duration)

          # Transcribe with whisper.cpp
          transcribe(temp_audio)
        ensure
          File.delete(temp_audio) if File.exists?(temp_audio)
        end
      end

      private def record_audio(output_path : String, duration : Int32) : Nil
        # Try different audio sources
        recorded = false

        # Try PulseAudio first (most common on Linux)
        unless recorded
          result = Process.run(
            "ffmpeg",
            ["-f", "pulse", "-i", "default", "-t", duration.to_s, "-y", output_path],
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )
          recorded = result.success? if File.exists?(output_path) && File.size(output_path) > 1000
        end

        # Try ALSA if Pulse failed
        unless recorded
          result = Process.run(
            "ffmpeg",
            ["-f", "alsa", "-i", "default", "-t", duration.to_s, "-y", output_path],
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )
          recorded = result.success? if File.exists?(output_path) && File.size(output_path) > 1000
        end

        # Try arecord as fallback
        unless recorded
          result = Process.run(
            "arecord",
            ["-d", duration.to_s, "-f", "cd", "-r", "16000", output_path],
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )
          recorded = result.success? if File.exists?(output_path) && File.size(output_path) > 1000
        end

        raise "Failed to record audio" unless recorded
      end

      private def transcribe(audio_path : String) : String
        return "" unless File.exists?(@whisper_path)

        # Run whisper.cpp
        result = Process.run(
          @whisper_path,
          ["-m", "base", "-f", audio_path, "-otxt"],
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Pipe
        )

        if result.success?
          # whisper.cpp outputs to a file with same name but .txt extension
          txt_path = audio_path.sub(".wav", ".txt")
          if File.exists?(txt_path)
            text = File.read(txt_path).strip
            File.delete(txt_path)
            return text
          end
        end

        ""
      end

      private def contains_wake_word?(text : String) : Bool
        text_lower = text.downcase
        wake_lower = @wake_word.downcase

        # Direct match
        return true if text_lower.includes?(wake_lower)

        # Handle common variations
        variations = [
          "hey #{wake_lower}",
          "ok #{wake_lower}",
          "#{wake_lower} please",
        ]

        variations.any? { |v| text_lower.includes?(v) }
      end

      private def extract_command(text : String) : String
        # Remove wake word and common filler words from the beginning
        wake_lower = @wake_word.downcase

        # Pattern: "hey crybot X" -> "X"
        # Pattern: "crybot please X" -> "X"
        # Pattern: "ok crybot X" -> "X"

        prefixes = [
          /^hey\s+#{wake_lower}\s*/i,
          /^ok\s+#{wake_lower}\s*/i,
          /^#{wake_lower}\s+please\s*/i,
          /^#{wake_lower}\s*/i,
        ]

        result = text
        prefixes.each do |pattern|
          if result =~ pattern
            result = result.sub(pattern, "").strip
            break
          end
        end

        result
      end

      private def process_command(command : String) : Nil
        if command.empty?
          puts "[Empty command, ignoring]"
          return
        end

        # Use a special session key for voice commands
        session_key = "voice"

        # Send to agent loop
        response = @agent_loop.process(session_key, command)

        # Output response
        puts
        puts "Response:"
        puts response
        puts
      end

      private def find_whisper_binary : String
        # Check common paths
        paths = [
          ENV["WHISPER_PATH"]?,
          File.expand_path("~/.local/bin/whisper"),
          "/usr/local/bin/whisper",
          "/usr/bin/whisper",
          File.expand_path("../whisper.cpp/whisper", Dir.current),
        ]

        paths.each do |path|
          if path && File.info?(path) && File.info(path).permissions.includes?(File::Permissions::OwnerExecute)
            return path
          end
        end

        raise "whisper.cpp binary not found. Please install whisper.cpp and set WHISPER_PATH environment variable"
      end
    end
  end
end
