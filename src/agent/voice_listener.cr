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
      @piper_model : String? = nil
      @piper_path : String = "/usr/bin/piper-tts"
      @conversational_timeout : Int32 = 3 # seconds

      def initialize(@agent_loop : Loop)
        @config = Config::Loader.load

        # Get configuration from config file (voice section)
        if voice_config = @config.voice
          @wake_word = voice_config.wake_word || "crybot"
          @whisper_stream_path = voice_config.whisper_stream_path || "/usr/bin/whisper-stream"
          @model_path = voice_config.model_path
          @language = voice_config.language || "en"
          @threads = voice_config.threads || 4
          @piper_model = voice_config.piper_model
          @piper_path = voice_config.piper_path || "/usr/bin/piper-tts"
          @conversational_timeout = voice_config.conversational_timeout || 3
        end

        # Find whisper-stream if not configured
        unless File.info?(@whisper_stream_path) && File.info(@whisper_stream_path).permissions.includes?(File::Permissions::OwnerExecute)
          @whisper_stream_path = find_whisper_stream
        end
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def start : Nil
        @running = true

        puts "Voice listener started"
        puts "  Wake word: '#{@wake_word}'"
        puts "  Model: #{@model_path || "default"}"
        puts "  Language: #{@language}"
        puts "  Say '#{@wake_word}' followed by your command"
        puts "  Press Ctrl+C to stop"
        puts "  Web UI push-to-talk also supported"
        puts "---"

        # Start whisper-stream process
        process = start_whisper_stream

        # Conversational mode: after a response, listen for follow-ups
        conversational_mode = false
        last_response_time = Time.unix(0)

        # Track transcriptions to avoid processing duplicates
        # We use a Set to track what we've already processed
        processed_transcriptions = Set(String).new
        pending_transcription = ""
        last_transcription_time = Time.unix(0)
        last_processed_time = Time.unix(0)

        # Push-to-talk flag file path
        ptt_flag_path = Config::Loader.config_dir / "voice_ptt_active"

        # Spawn a fiber to manage conversational timeout, check push-to-talk, and flush pending transcriptions
        spawn do
          while @running
            sleep 0.1.seconds

            # Check push-to-talk flag from web UI
            ptt_active = File.exists?(ptt_flag_path)

            if ptt_active && !conversational_mode
              conversational_mode = true
              puts "--- [Push-to-talk activated]"
            elsif !ptt_active && conversational_mode && (Time.utc - last_response_time) > @conversational_timeout.seconds
              conversational_mode = false
              puts "--- [Conversational window closed, say '#{@wake_word}' or use push-to-talk to activate]"
            end

            # Flush pending transcription after 1.5 seconds of silence
            # Also ensure we don't process too frequently (min 1.5s between processes)
            if !pending_transcription.empty? && (Time.utc - last_transcription_time) > 1.5.seconds && (Time.utc - last_processed_time) > 1.5.seconds
              unless processed_transcriptions.includes?(pending_transcription)
                process_transcription(pending_transcription, conversational_mode)
                processed_transcriptions.add(pending_transcription)
                last_processed_time = Time.utc

                if contains_wake_word?(pending_transcription) && !conversational_mode
                  conversational_mode = true
                  last_response_time = Time.utc
                  puts "--- [Conversational window open (#{@conversational_timeout}s)]"
                  puts "--- Listening for wake word..."
                end
              end
              pending_transcription = ""
            end
          end
        end

        begin
          process.output.each_line do |line|
            break unless @running

            line = line.strip
            next if line.empty?

            # Clean whisper-stream output (remove ANSI escape codes)
            cleaned_line = clean_transcription(line)
            next if cleaned_line.empty?

            # Skip very short transcriptions (likely noise)
            next if cleaned_line.size < 3

            # Skip if already processed
            next if processed_transcriptions.includes?(cleaned_line)

            # Update pending transcription (keep the longest version)
            if cleaned_line.size > pending_transcription.size
              pending_transcription = cleaned_line
              last_transcription_time = Time.utc
            end
          end
        rescue e : Exception
          puts "[Error reading from whisper-stream: #{e.message}]"
        ensure
          process.terminate if process.exists?
          # Clean up push-to-talk flag
          File.delete(ptt_flag_path) if File.exists?(ptt_flag_path)
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
          error: Process::Redirect::Pipe # Capture stderr instead of inheriting
        )
      end

      private def build_whisper_args : Array(String)
        # Get whisper options from config, with defaults
        config = @config
        step_ms = config.voice.try(&.step_ms) || 3000
        audio_length_ms = config.voice.try(&.audio_length_ms) || 10000
        audio_keep_ms = config.voice.try(&.audio_keep_ms) || 200
        vad_threshold = config.voice.try(&.vad_threshold) || 0.6_f32

        args = [
          "-c", @threads.to_s,
          "-l", @language,
          "--step", step_ms.to_s,
          "--length", audio_length_ms.to_s,
          "--keep", audio_keep_ms.to_s,
          "--vad-thold", vad_threshold.to_s,
        ]

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

        # Log incoming voice command
        puts "[Voice] User: #{command}"

        # Send to agent loop (the filtering improvements should handle most errors)
        agent_response = @agent_loop.process(session_key, command)

        # Log response
        response_preview = agent_response.response.size > 200 ? "#{agent_response.response[0..200]}..." : agent_response.response
        puts "[Voice] Assistant: #{response_preview}"

        # Log tool executions
        agent_response.tool_executions.each do |exec|
          status = exec.success? ? "✓" : "✗"
          puts "[Tool] #{status} #{exec.tool_name}"
          if exec.tool_name == "exec" || exec.tool_name == "exec_shell"
            args_str = exec.arguments.map { |k, v| "#{k}=#{v}" }.join(" ")
            puts "       Command: #{args_str}"
            result_preview = exec.result.size > 200 ? "#{exec.result[0..200]}..." : exec.result
            puts "       Output: #{result_preview}"
          end
        end

        response = agent_response.response

        # Check if there were any tool execution errors
        has_errors = agent_response.tool_executions.any? { |exec| !exec.success? }

        # Output response
        puts
        puts "Response:"
        puts response
        puts

        # Speak the response (or error message if tools failed)
        if has_errors
          speak("There was an error. You can see the details in the web UI.")
        else
          speak(response)
        end
      end

      private def process_transcription(text : String, conversational_mode : Bool) : Nil
        # whisper-stream outputs transcriptions
        puts "[Heard: #{text}]"

        if conversational_mode
          # In conversational mode, treat everything as a command
          puts "[Conversational mode: #{text}]"
          process_command(text)
        elsif contains_wake_word?(text)
          # Wake word detected! Extract command from same line
          clean_command = extract_command(text)
          puts "[Wake word detected! Command: #{clean_command}]"

          unless clean_command.empty?
            process_command(clean_command)
          end
        end
      end

      private def speak(text : String) : Nil
        # Clean up text for speech (remove markdown, code blocks, etc.)
        clean_text = clean_for_speech(text)

        # Skip if empty
        return if clean_text.empty?

        # Check if piper is available
        if model = @piper_model
          if File.info?(@piper_path) && File.info(@piper_path).permissions.includes?(File::Permissions::OwnerExecute)
            speak_with_piper(clean_text, model)
          else
            speak_with_festival(clean_text)
          end
        else
          speak_with_festival(clean_text)
        end
      rescue e : Exception
        # Don't fail if TTS doesn't work
        puts "[TTS Error: #{e.message}]"
      end

      private def speak_with_piper(text : String, model : String) : Nil
        # Pipe piper raw output directly to paplay
        # Add --sentence_silence 0 to reduce pauses between sentences (faster speech)
        Process.run(
          "sh",
          ["-c", "echo \"#{text.gsub("\"", "\\\"")}\" | #{@piper_path} -m #{model} --output_raw --sentence_silence 0 2>/dev/null | paplay --raw --format=s16le --channels=1 --rate=22050"],
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
      end

      private def speak_with_festival(text : String) : Nil
        # Write to temp file and have festival read it
        temp_file = File.join(Dir.tempdir, "crybot_tts_#{Process.pid}.txt")
        File.write(temp_file, text)

        Process.run("festival", ["--tts", temp_file], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit)
        File.delete(temp_file)
      end

      private def play_audio(file_path : String) : Nil
        # Try different audio players
        players = [
          {"paplay", [] of String},             # PulseAudio
          {"aplay", [] of String},              # ALSA
          {"ffplay", ["-nodisp", "-autoexit"]}, # ffmpeg
          {"mpg123", [] of String},             # mp3 player (also plays wav)
        ]

        players.each do |(player, args)|
          result = Process.run(
            player,
            args + [file_path],
            output: Process::Redirect::Pipe,
            error: Process::Redirect::Pipe
          )
          return if result.success?
        end
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

      private def clean_transcription(text : String) : String
        # Remove ANSI escape codes (like \u001b[2K\r)
        # These are used by whisper-stream for line clearing/redrawing
        text = text.gsub(/\e\[[0-9;]*[A-Za-z]/, "") # CSI sequences
        text = text.gsub(/\e\[K/, "")               # EL (erase to end of line)
        text = text.gsub(/\r\$/, "")                # trailing CR
        text = text.gsub(/\[2K\r/, "")              # literal [2K\r (sometimes not escaped)
        text = text.strip

        # Also clean up the [BLANK_AUDIO] placeholder if present
        text = text.gsub(/\[BLANK_AUDIO\]/, "").strip

        # Filter out anything in parentheses (non-speech sounds like "(wind blowing)")
        # Remove text within parentheses
        text = text.gsub(/\([^)]*\)/, "").strip

        # Remove leading punctuation and spaces (common with partial transcriptions)
        # This handles ", try my joke." -> "try my joke."
        text = text.gsub(/^[,\.\s]+/, "").strip

        # If nothing left after cleaning, return empty
        return "" if text.empty?

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
