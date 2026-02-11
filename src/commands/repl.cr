require "log"
require "../config/loader"
require "../agent/loop"
require "fancyline"

module Crybot
  module Commands
    class Repl
      def self.start : Nil
        # Load config
        config = Config::Loader.load

        # Check API key based on model
        model = config.agents.defaults.model
        provider = detect_provider_from_model(model)

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
          Log.error { "Error: API key not configured for provider '#{provider}'." }
          Log.error { "Please edit #{Config::Loader.config_file} and add your API key" }
          return
        end

        # Create agent loop
        agent_loop = Crybot::Agent::Loop.new(config)

        # Start the REPL with a new instance
        new(agent_loop, model).run
      end

      def self.detect_provider_from_model(model : String) : String
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

      def initialize(@agent_loop : Crybot::Agent::Loop, @model : String)
        @session_key = "repl"
        @fancy = Fancyline.new
        @running = true

        # Setup display widgets
        setup_display

        # Setup autocompletion
        setup_autocompletion

        # Load history
        load_history
      end

      # ameba:disable Metrics/CyclomaticComplexity
      def run : Nil
        Log.info { "Crybot REPL - Model: #{@model}" }
        Log.info { "Type 'quit', 'exit', or press Ctrl+D to end the session." }
        Log.info { "Type 'help' for available commands." }
        Log.info { "---" }

        begin
          while @running
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
              print "Thinking..."

              begin
                response = @agent_loop.process(@session_key, input)
                print "\r" + " " * 20 + "\r" # Clear the "Thinking..." message

                # Print response with formatting
                puts
                puts response
                puts
              rescue e : Fancyline::Interrupt
                # Ctrl+C pressed during input
                puts ""
                puts "Use 'quit' or 'exit' to exit, or Ctrl+D"
                puts
              rescue e : Exception
                puts ""
                Log.error(exception: e) { "Error: #{e.message}" }
                Log.debug(exception: e) { e.backtrace.join("\n") } if ENV["DEBUG"]?
                puts
              end
            rescue e : Fancyline::Interrupt
              # Ctrl+C pressed during input
              puts ""
              Log.info { "Use 'quit' or 'exit' to exit, or Ctrl+D" }
              puts
            rescue e : Exception
              puts ""
              Log.error(exception: e) { "Error: #{e.message}" }
              Log.debug(exception: e) { e.backtrace.join("\n") } if ENV["DEBUG"]?
              puts
            end
          end

          # Save history before exiting
          save_history
        ensure
          Log.info { "Goodbye!" }
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
          @running = false
          return true
        when "clear"
          system("clear")
          return true
        when "help"
          show_help
          return true
        when "model"
          Log.info { "Current model: #{@model}" }
          Log.info { "" }
          return true
        end

        false
      end

      private def show_help : Nil
        Log.info { "Available commands:" }
        Log.info { "  help   - Show this help message" }
        Log.info { "  model  - Show current model" }
        Log.info { "  clear  - Clear the screen" }
        Log.info { "  quit   - Exit the REPL" }
        Log.info { "  exit   - Exit the REPL" }
        Log.info { "  Tab    - Autocomplete commands" }
        Log.info { "  Up/Down - Navigate command history" }
        Log.info { "  Ctrl+R - Search history" }
        Log.info { "  Ctrl+L - Clear screen" }
        Log.info { "" }
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
