require "../config/loader"
require "../agent/loop"
require "../features/repl"

module Crybot
  module Commands
    class Agent
      def self.execute(message : String?) : Nil
        # Load config
        config = Config::Loader.load

        # Check API key
        if config.providers.zhipu.api_key.empty?
          puts "Error: z.ai API key not configured."
          puts "Please edit #{Config::Loader.config_file} and add your API key under providers.zhipu.api_key"
          puts "Get your API key from https://open.bigmodel.cn/"
          return
        end

        # Create agent loop
        agent_loop = Crybot::Agent::Loop.new(config)

        if message
          # Non-interactive mode: single message
          session_key = "cli"

          # Animated spinner
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

          agent_response = agent_loop.process(session_key, message)

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

          print "\r" + " " * 30 + "\r" # Clear the spinner line
          puts agent_response.response
        else
          # Interactive mode - use the fancyline REPL
          run_fancyline_repl(agent_loop, config)
        end
      end

      private def self.run_fancyline_repl(agent_loop : Crybot::Agent::Loop, config : Config::ConfigFile) : Nil
        model = config.agents.defaults.model
        # Create a custom REPL instance with "agent" session key
        # Use ->{ true } as running_check so it continues until user quits
        repl_instance = Features::ReplFeature::ReplInstance.new(agent_loop, model, "agent", ->{ true })

        # Check if stdin is a TTY (interactive terminal)
        if STDIN.tty?
          repl_instance.run
        else
          # Non-interactive mode (piped input), fall back to simple mode
          run_simple_interactive(agent_loop)
        end
      end

      private def self.run_simple_interactive(agent_loop : Crybot::Agent::Loop) : Nil
        session_key = "agent"

        puts "Crybot Agent Mode"
        puts "Type 'quit' or 'exit' to end the session."
        puts "---"

        loop do
          print "> "
          input = gets

          break if input.nil?

          input = input.strip

          break if input == "quit" || input == "exit"
          next if input.empty?

          begin
            # Animated spinner
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

            agent_response = agent_loop.process(session_key, input)

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

            print "\r" + " " * 30 + "\r" # Clear the spinner line
            puts agent_response.response
            puts
          rescue e : Exception
            puts "Error: #{e.message}"
            puts e.backtrace.join("\n") if ENV["DEBUG"]?
          end
        end
      end
    end
  end
end
