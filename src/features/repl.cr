require "../agent/loop"
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
          @repl_instance = ReplInstance.new(agent_loop, model, "repl", ->{ @running })

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

        def initialize(@agent_loop : Crybot::Agent::Loop, @model : String, @session_key : String = "repl", @running_check : Proc(Bool) = ->{ true })
          @fancy = Fancyline.new

          # Setup display widgets
          setup_display

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

          begin
            while @running_check.call
              begin
                input = @fancy.readline(prompt_string)

                if input.nil?
                  # Ctrl+D pressed
                  puts ""
                  break
                end

                input = input.to_s.strip
                next if input.empty?

                # Handle built-in commands
                if handle_command(input)
                  next
                end

                # Process the message
                # Show animated spinner while thinking
                spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
                spinner_idx = 0
                spinning = true
                spawn do
                  while spinning
                    print "\r#{spinner[spinner_idx % spinner.size]} Thinking..."
                    spinner_idx += 1
                    sleep 0.1.seconds
                  end
                end

                begin
                  agent_response = @agent_loop.process(@session_key, input)

                  # Stop spinner
                  spinning = false
                  sleep 0.15.seconds # Let the spinner finish one more cycle

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
                rescue e : Fancyline::Interrupt
                  # Stop spinner
                  spinning = false
                  sleep 0.15.seconds
                  # Ctrl+C pressed during input
                  puts ""
                  puts "Use 'quit' or 'exit' to exit, or Ctrl+D"
                  puts
                rescue e : Exception
                  # Stop spinner
                  spinning = false
                  sleep 0.15.seconds
                  puts ""
                  puts "Error: #{e.message}"
                  puts e.backtrace.join("\n") if ENV["DEBUG"]?
                  puts
                end
              rescue e : Fancyline::Interrupt
                # Ctrl+C pressed during input
                puts ""
                puts "Use 'quit' or 'exit' to exit, or Ctrl+D"
                puts
              rescue e : Exception
                puts ""
                puts "Error: #{e.message}"
                puts e.backtrace.join("\n") if ENV["DEBUG"]?
                puts
              end
            end

            # Save history before exiting
            save_history
          ensure
            puts "REPL terminated"
          end
        end

        private def setup_display : Nil
          # Add syntax highlighting for the input
          @fancy.display.add do |ctx, line, yielder|
            # Colorize built-in commands
            line = line.gsub(/\b(help|clear|model|quit|exit)\b/) do |cmd|
              cmd.colorize(:cyan)
            end

            # Call next middleware
            yielder.call(ctx, line)
          end
        end

        private def setup_autocompletion : Nil
          @fancy.autocomplete.add do |ctx, range, word, yielder|
            completions = yielder.call(ctx, range, word)

            # Built-in commands
            commands = ["help", "clear", "model", "quit", "exit"]

            # Add command completions if word matches
            if word_matches_command(word)
              commands.each do |cmd|
                if cmd.starts_with?(word) && cmd != word
                  completions << Fancyline::Completion.new(range, cmd, cmd.colorize(:cyan).to_s)
                end
              end
            end

            completions
          end
        end

        private def word_matches_command(word : String) : Bool
          return true if word.empty?

          commands = ["help", "clear", "model", "quit", "exit"]
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

          false
        end

        private def show_help : Nil
          puts "Available commands:"
          puts "  help   - Show this help message"
          puts "  model  - Show current model"
          puts "  clear  - Clear the screen"
          puts "  quit   - Exit the REPL"
          puts "  exit   - Exit the REPL"
          puts "  Tab    - Autocomplete commands"
          puts "  Up/Down - Navigate command history"
          puts "  Ctrl+R - Search history"
          puts "  Ctrl+L - Clear screen"
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
