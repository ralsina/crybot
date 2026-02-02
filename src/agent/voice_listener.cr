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
      @whisper_stream_path : String = "/usr/bin/whisper-stream"
      @model_path : String?
      @language : String = "en"
      @threads : Int32 = 4

      def initialize(@agent_loop : Loop)
        @config = Config::Loader.load

        # Get configuration from config file (voice section)
        if voice_config = @config.voice
          @wake_word = voice_config.wake_word || "crybot"
          @whisper_stream_path = voice_config.whisper_stream_path || "/usr/bin/whisper-stream"
          @model_path = voice_config.model_path
          @language = voice_config.language || "en"
          @threads = voice_config.threads || 4
        end

        # Find whisper-stream if not configured
        unless File.info?(@whisper_stream_path) && File.info(@whisper_stream_path).permissions.includes?(File::Permissions::OwnerExecute)
          @whisper_stream_path = find_whisper_stream
        end
      end

      def start : Nil
        @running = true

        puts "Voice listener started"
        puts "  Wake word: '#{@wake_word}'"
        puts "  Model: #{@model_path || "default"}"
        puts "  Language: #{@language}"
        puts "  Say '#{@wake_word}' followed by your command"
        puts "  Press Ctrl+C to stop"
        puts "---"

        # Start whisper-stream process
        process = start_whisper_stream

        begin
          process.output.each_line do |line|
            break unless @running

            line = line.strip
            next if line.empty?

            # whisper-stream outputs transcriptions
            puts "[Heard: #{line}]"

            if contains_wake_word?(line)
              # Wake word detected! Extract command from same line
              clean_command = extract_command(line)
              puts "[Wake word detected! Command: #{clean_command}]"

              unless clean_command.empty?
                process_command(clean_command)
              end

              puts "--- Listening for wake word..."
            end
          end
        rescue e : Exception
          puts "[Error reading from whisper-stream: #{e.message}]"
        ensure
          process.terminate if process.exists?
        end
      end

      def stop : Nil
        @running = false
        puts "Voice listener stopped"
      end

      private def start_whisper_stream : Process
        args = build_whisper_args

        Process.new(
          @whisper_stream_path,
          args,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Inherit
        )
      end

      private def build_whisper_args : Array(String)
        args = ["-c", @threads.to_s, "-l", @language]

        if model = @model_path
          args += ["-m", model]
        end

        args
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
          "wake up #{wake_lower}",
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
          /^wake up\s+#{wake_lower}\s*/i,
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

        # Speak the response
        speak(response)
      end

      private def speak(text : String) : Nil
        # Clean up text for speech (remove markdown, code blocks, etc.)
        clean_text = clean_for_speech(text)

        # Write to temp file and have festival read it
        temp_file = File.join(Dir.tempdir, "crybot_tts_#{Process.pid}.txt")
        File.write(temp_file, clean_text)

        Process.run("festival", ["--tts", temp_file], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        File.delete(temp_file)
      rescue e : Exception
        # Don't fail if TTS doesn't work
        puts "[TTS Error: #{e.message}]"
      end

      private def clean_for_speech(text : String) : String
        # Remove markdown code blocks
        text = text.gsub(/```[\s\S]*?```/, "")
        # Remove inline code
        text = text.gsub(/`[^`]+`/, "")
        # Remove other markdown symbols
        text = text.gsub(/\*\*([^*]+)\*\*/, "\\1") # bold
        text = text.gsub(/\*([^*]+)\*/, "\\1")     # italic
        text = text.gsub(/`([^`]+)`/, "\\1")       # inline code
        # Clean up extra whitespace
        text = text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n")
        text
      end

      private def find_whisper_stream : String
        # Check common paths
        paths = [
          "/usr/bin/whisper-stream",
          "/usr/local/bin/whisper-stream",
          File.expand_path("~/.local/bin/whisper-stream"),
          File.expand_path("../whisper.cpp/whisper-stream", Dir.current),
        ]

        paths.each do |path|
          if File.info?(path) && File.info(path).permissions.includes?(File::Permissions::OwnerExecute)
            return path
          end
        end

        raise "whisper-stream not found. Please install whisper.cpp or set voice.whisper_stream_path in config"
      end
    end
  end
end
