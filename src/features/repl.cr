require "../agent/loop"
require "../agent/cancellation"
require "../session/manager"
require "../session/metadata"
require "fancyline"
require "./base"

module Crybot
  module Features
    class ReplFeature < FeatureModule
      @config : Config::ConfigFile
      @agent_loop : Agent::Loop?
      @repl_instance : ReplInstance?
      @repl_fiber : Fiber?

      def initialize(@config : Config::ConfigFile)
      end

      def start : Nil
        return unless validate_config(@config)

        puts "[#{Time.local.to_s("%H:%M:%S")}] Starting REPL feature..."

        # Create agent loop
        @agent_loop = Agent::Loop.new(@config)

        # Create and start REPL in a fiber
        agent_loop = @agent_loop
        if agent_loop
          model = @config.agents.defaults.model
          @repl_instance = ReplInstance.new(agent_loop, model, "repl", -> { @running })

          @repl_fiber = spawn do
            @repl_instance.try(&.run)
          end
        end

        @running = true
      end

      def stop : Nil
        @running = false
        # The REPL checks the running flag in its loop
      end

      private def validate_config(config : Config::ConfigFile) : Bool
        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider(model)

        api_key_valid = case provider
                        when "openai"
                          !config.providers.openai.api_key.empty?
                        when "anthropic"
                          !config.providers.anthropic.api_key.empty?
                        when "openrouter"
                          !config.providers.openrouter.api_key.empty?
                        when "vllm"
                          !config.providers.vllm.api_base.empty?
                        else # zhipu (default)
                          !config.providers.zhipu.api_key.empty?
                        end

        unless api_key_valid
          puts "Error: API key not configured for provider '#{provider}'."
          puts "Please edit #{Config::Loader.config_file} and add your API key"
          return false
        end

        true
      end

      private def detect_provider(model : String) : String
        parts = model.split('/', 2)
        provider = parts.size == 2 ? parts[0] : nil

        provider || case model
        when /^gpt-/      then "openai"
        when /^claude-/   then "anthropic"
        when /^glm-/      then "zhipu"
        when /^deepseek-/ then "openrouter"
        when /^qwen-/     then "openrouter"
        else                   "zhipu"
        end
      end

      # Inner class that contains the actual REPL logic
      # Public so it can be reused by the agent command
      class ReplInstance
        @agent_loop : Crybot::Agent::Loop
        @model : String
        @session_key : String
        @fancy : Fancyline
        @running_check : Proc(Bool)
        @sessions : Session::Manager

        def initialize(@agent_loop : Crybot::Agent::Loop, @model : String, @session_key : String = "repl", @running_check : Proc(Bool) = -> { true })
          @fancy = Fancyline.new
          @sessions = Session::Manager.instance

          # Setup display widgets
          self.setup_display

          # Setup autocompletion
          setup_autocompletion

          # Load history
          load_history
        end

        # ameba:disable Metrics/CyclomaticComplexity
        def run : Nil
          puts "Crybot REPL - Model: #{@model}"
          puts "Type 'quit', 'exit', or press Ctrl+D to end the session."
          puts "Type 'help' for available commands."
          puts "---"

          while @running_check.call
            begin
              input = @fancy.readline(prompt_string)

              if input.nil?
                # Ctrl+D pressed
                puts ""
                break
              end

              input_string = input.to_s.strip
              next if input_string.empty?

              # Handle built-in commands
              if handle_command(input_string)
                next
              end

              # Process the message
              # Show animated spinner while thinking
              spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
              spinner_idx = 0

              # Channels for fiber communication
              response_channel = Channel(Agent::AgentResponse?).new
              cancel_channel = Channel(Nil).new
              done_channel = Channel(Nil).new

              # Spawn the agent request in a background fiber
              spawn do
                begin
                  response = @agent_loop.process(@session_key, input_string)
                  response_channel.send(response)
                rescue e : Exception
                  # Send nil on error
                  response_channel.send(nil)
                end
              end

              # Spawn input reader fiber to catch Ctrl+K during request
              spawn do
                begin
                  # Set terminal to raw mode for non-blocking input
                  if STDIN.tty?
                    system("stty raw -echo 2>/dev/null")
                  end

                  loop do
                    # Check if request is done
                    select
                    when _ = response_channel.receive?
                      has_response = true
                      break
                    when timeout(0.01.seconds)
                      # Continue checking for input
                    end
                    break if has_response

                    # Try to read a byte non-blocking
                    begin
                      byte = STDIN.read_byte
                      if byte == 11 # Ctrl+K (ASCII 11, VT character)
                        Agent::CancellationManager.cancel_current
                        print "\r" + " " * 50 + "\r"
                        puts "⚠ Cancelling..."
                        # Send twice: once for spinner, once for main fiber
                        cancel_channel.send(nil)
                        cancel_channel.send(nil)
                        break
                      end
                    rescue
                      # No input available, continue
                    end

                    sleep 0.05.seconds
                  end
                ensure
                  # Restore terminal settings
                  system("stty sane 2>/dev/null")
                end
              end

              # Spawn spinner fiber
              spawn do
                loop do
                  print "\r#{spinner[spinner_idx % spinner.size]} Thinking... (Ctrl+K to cancel)"
                  spinner_idx += 1
                  sleep 0.1.seconds

                  # Check if request is done or cancelled
                  select
                  when _ = done_channel.receive?
                    done = true
                  when _ = cancel_channel.receive?
                    cancelled = true
                  when timeout(0.05.seconds)
                    # just timeout
                  end
                  break if done || cancelled
                end
              end

              # Main fiber waits for either response or cancellation
              select
              when r = response_channel.receive
                agent_response = r
                # Signal spinner fiber to stop
                done_channel.send(nil)
              when cancel_channel.receive
                cancelled = true
              end

              # Ensure terminal is restored
              system("stty sane 2>/dev/null")

              # Give spinner fiber a moment to stop
              sleep 0.15.seconds

              if cancelled
                # Request was cancelled - wait for response to arrive but discard it
                spawn do
                  response_channel.receive?
                end
                puts
                puts "Request cancelled."
                puts
                next
              end

              if agent_response
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

                # Clear the spinner line
                print "\r" + " " * 30 + "\r"

                # Print response with formatting
                puts
                puts agent_response.response
                puts
              else
                puts ""
                puts "Error: No response from agent."
                puts
              end
            rescue e : Fancyline::Interrupt
              # Ensure terminal mode is restored
              puts
            rescue e : Exception
              # Ensure terminal mode is restored
              system("stty sane 2>/dev/null")
              # Signal completion to fibers
              puts ""
              puts "Error: #{e.message}"
              puts e.backtrace.join("\n") if ENV["DEBUG"]?
              puts
            end
          end
        rescue ex : Fancyline::Interrupt
          # Ctrl+C pressed during input
          puts ""
          puts "Use 'quit' or 'exit' to exit, or Ctrl+D"
          puts
        rescue error : Exception
          puts ""
          puts "Error: #{error.message}"
          puts error.backtrace.join("\n") if ENV["DEBUG"]?
          puts

          # Save history before exiting
          save_history
        ensure
          puts "REPL terminated"
        end

        protected def setup_display : Nil
          # Add syntax highlighting for the input
          @fancy.display.add do |ctx, line, yielder|
            # Colorize built-in commands
            line = line.gsub(/\b(help|clear|model|quit|exit)\b/) do |cmd|
              cmd.colorize(:cyan)
            end

            # Colorize slash commands
            line = line.gsub(/\/(title|description|info)\b/) do |cmd|
              cmd.colorize(:yellow)
            end

            # Call next middleware
            yielder.call(ctx, line)
          end
        end

        private def setup_autocompletion : Nil
          # Add Ctrl+K key binding for cancellation (K for Kill)
          @fancy.actions.set Fancyline::Key::Control::CtrlK do
            # Trigger cancellation
            Agent::CancellationManager.cancel_current
            # Note: This sets the flag that the agent loop will check
            # on the next iteration or during retry delays
            puts "\n⚠ Cancelling..."
            # Raise interrupt to exit readline
            raise Fancyline::Interrupt.new("Request cancelled")
          end

          @fancy.autocomplete.add do |ctx, range, word, yielder|
            completions = yielder.call(ctx, range, word)

            # Built-in commands
            commands = ["help", "clear", "model", "quit", "exit"]

            # Slash commands
            slash_commands = ["/title", "/description", "/info"]

            # Add command completions if word matches
            if word_matches_command(word, commands)
              commands.each do |cmd|
                if cmd.starts_with?(word) && cmd != word
                  completions << Fancyline::Completion.new(range, cmd, cmd.colorize(:cyan).to_s)
                end
              end
            end

            # Add slash command completions
            if word.starts_with?("/")
              slash_commands.each do |cmd|
                if cmd.starts_with?(word) && cmd != word
                  completions << Fancyline::Completion.new(range, cmd, cmd.colorize(:yellow).to_s)
                end
              end
            end

            completions
          end
        end

        private def word_matches_command(word : String, commands : Array(String)) : Bool
          return true if word.empty?
          commands.any?(&.starts_with?(word))
        end

        private def prompt_string : String
          # Show current model in prompt with colors
          model_short = @model.split('/').last
          model_short = model_short[0..15] if model_short.size > 15
          "[#{model_short}] ".colorize(:blue).to_s + "❯ ".colorize(:green).to_s
        end

        private def handle_command(input : String) : Bool
          case input
          when "quit", "exit"
            # Don't set running directly, the coordinator will stop us
            return true
          when "clear"
            system("clear")
            return true
          when "help"
            show_help
            return true
          when "model"
            puts "Current model: #{@model}"
            puts
            return true
          end

          # Handle slash commands
          if input.starts_with?("/")
            return handle_slash_command(input)
          end

          false
        end

        # ameba:disable Metrics/CyclomaticComplexity
        private def handle_slash_command(input : String) : Bool
          parts = input.split(' ', 2)
          command = parts[0]
          args = parts.size > 1 ? parts[1]? : ""

          case command
          when "/title"
            if args.nil? || args.empty?
              metadata = @sessions.get_metadata(@session_key)
              puts "Current title: #{metadata.title}"
            else
              @sessions.update_title(@session_key, args)
              puts "✓ Title updated to: #{args}"
            end
            return true
          when "/description"
            if args.nil? || args.empty?
              metadata = @sessions.get_metadata(@session_key)
              puts "Current description: #{metadata.description}"
              if metadata.description.empty?
                puts "  (no description set)"
              end
            else
              @sessions.update_description(@session_key, args)
              puts "✓ Description updated"
            end
            return true
          when "/info"
            metadata = @sessions.get_metadata(@session_key)
            puts "Session information:"
            puts "  Title: #{metadata.title}"
            puts "  Description: #{metadata.description.empty? ? "(none)" : metadata.description}"
            puts "  Last updated: #{metadata.updated_at}"
            return true
          end

          false
        end

        private def show_help : Nil
          puts "Available commands:"
          puts "  help   - Show this help message"
          puts "  model  - Show current model"
          puts "  clear  - Clear the screen"
          puts "  quit   - Exit the REPL"
          puts "  exit   - Exit the REPL"
          puts
          puts "Slash commands:"
          puts "  /title [text]      - Set or view conversation title"
          puts "  /description [text] - Set or view conversation description"
          puts "  /info              - Show session information"
          puts
          puts "Other:"
          puts "  Tab    - Autocomplete commands"
          puts "  Up/Down - Navigate command history"
          puts "  Ctrl+R - Search history"
          puts "  Ctrl+L - Clear screen"
          puts "  Ctrl+K - Cancel current LLM request (during processing)"
          puts
        end

        private def history_file : Path
          Config::Loader.config_dir / "repl_history.txt"
        end

        private def load_history : Nil
          hist_file = history_file
          if File.exists?(hist_file)
            begin
              File.open(hist_file, "r") do |io|
                @fancy.history.load(io)
              end
            rescue e : Exception
              # Ignore history loading errors
            end
          end
        end

        private def save_history : Nil
          hist_file = history_file
          begin
            File.open(hist_file, "w") do |io|
              @fancy.history.save(io)
            end
          rescue e : Exception
            # Ignore history saving errors
          end
        end
      end
    end
  end
end
