require "log"
require "docopt"
require "./config/loader"
require "./crysh/provider_factory"
require "./crysh/rofi"

# Setup logging from environment
Log.setup_from_env

DOC = <<-DOC
Crysh - Natural Language Shell Wrapper

Generates shell commands from natural language descriptions using LLMs.

Usage:
  crysh [-y] [--dry-run] [-v] <description>
  crysh [-h | --help]

Options:
  -h --help        Show this help message
  -y               Skip confirmation and execute immediately (use with caution)
  --dry-run        Show the generated command without executing it
  -v               Verbose mode: show detailed logging for debugging

Arguments:
  description      Natural language description of the desired shell operation

Examples:
  crysh "get the second field of stdin separated by commas"
  crysh "sort lines in reverse order"
  crysh "count unique lines in stdin"

The generated command will be shown in a rofi dialog for confirmation before execution.
Use -y to skip confirmation (useful in scripts or for testing).
Use --dry-run to preview the command without executing.
Use -v for verbose logging to debug issues.
DOC

module Crybot
  module Crysh
    Log = ::Log.for("crysh")

    def self.run : Nil
      args = ARGV

      # Check for flags
      skip_confirmation = args.includes?("-y")
      dry_run = args.includes?("--dry-run")
      verbose = args.includes?("-v")
      args_without_flags = args.reject { |arg| arg == "-y" || arg == "--dry-run" || arg == "-v" }

      # Configure logging based on flags
      if dry_run
        # Suppress all logging for clean output
        ::Log.setup("*", ::Log::Severity::Fatal)
      elsif verbose
        # Enable detailed logging for debugging
        ::Log.setup("*", ::Log::Severity::Debug)
      else
        # For normal usage, only show warnings and errors to reduce noise
        ::Log.setup("*", ::Log::Severity::Warn)
      end

      # Show help if requested
      if args_without_flags.includes?("-h") || args_without_flags.includes?("--help")
        puts DOC
        return
      end

      # Get description from arguments
      description = args_without_flags[0]?
      if description.nil?
        STDERR.puts "Error: No description provided"
        puts "\n" + DOC
        exit 1
      end

      # Load config
      config = Config::Loader.load

      # Create provider
      provider = ProviderFactory.create_provider(config)

      # Generate command
      command = generate_command(provider, description, config)

      # Handle --dry-run: just show the command and exit
      if dry_run
        puts command
        exit 0
      end

      # Confirm with rofi (unless -y flag is set)
      final_command = if skip_confirmation
                        Log.debug { "Skipping confirmation due to -y flag" }
                        command
                      else
                        confirmed_command = Rofi.confirm(command)
                        if confirmed_command.nil?
                          Log.info { "Operation cancelled by user" }
                          exit 0
                        end
                        confirmed_command
                      end

      # Execute the command
      execute_command(final_command)
    rescue e : Exception
      Log.error(exception: e) { "Error: #{e.message}" }
      Log.debug(exception: e) { e.backtrace.join("\n") } if ENV["DEBUG"]?
      exit 1
    end

    private def self.generate_command(provider : Providers::LLMProvider, description : String, config : Config::ConfigFile) : String
      Log.info { "Generating command for: #{description}" }

      system_prompt = <<-SYSTEM
You are a shell command generator. Given a natural language description, generate the appropriate shell command.

IMPORTANT RULES:
1. Return ONLY the shell command, nothing else - no explanations, no markdown formatting
2. Assume the command will receive data on stdin and should output to stdout
3. Use common Unix tools (awk, sed, grep, cut, sort, uniq, etc.)
4. Keep commands simple and efficient
5. If the description is ambiguous, choose the most reasonable interpretation
6. CRITICAL: Ensure all quotes are properly balanced and closed
7. Always double-check that single quotes and double quotes are paired correctly

Examples:
Description: "get the second field of stdin separated by commas"
Command: cut -d, -f2

Description: "sort lines in reverse order"
Command: sort -r

Description: "count unique lines in stdin"
Command: sort | uniq -c

Description: "print the longest line"
Command: awk 'length>max{max=length;line=$0}END{print line}'

Now generate a command for this description:
SYSTEM

      messages = [
        Providers::Message.new("system", system_prompt),
        Providers::Message.new("user", description),
      ]

      model = config.agents.defaults.model
      response = provider.chat(messages, nil, model)

      content = response.content
      if content.nil?
        raise "LLM returned empty response"
      end

      # Clean up the response - remove markdown formatting, extra whitespace
      command = content.strip

      # Remove markdown code blocks if present
      command = command.gsub(/^```(?:bash|sh)?\n/, "").gsub(/```$/, "")

      # Remove any leading/trailing quotes that might have been added
      command = command.gsub(/^["']|["']$/, "")

      command = command.strip

      # Fix common quote issues
      command = fix_command_quotes(command)

      Log.debug { "Generated command: #{command}" }

      # Basic validation - command should not be empty
      if command.empty?
        raise "Generated command is empty"
      end

      command
    end

    # Fix common quote issues in generated commands
    private def self.fix_command_quotes(command : String) : String
      # Count single quotes
      single_quotes = command.count("'")

      # If odd number of single quotes, try to fix
      if single_quotes.odd?
        Log.debug { "Odd number of single quotes detected, attempting to fix" }

        # If command ends with a pattern that looks like it needs a closing quote
        # Common awk pattern: '...' without closing quote
        if command =~ /^awk\s+'[^']*$/ && !command.ends_with?("'")
          command += "'"
          Log.debug { "Added missing closing quote" }
        elsif command =~ /^sed\s+'[^']*$/ && !command.ends_with?("'")
          command += "'"
          Log.debug { "Added missing closing quote to sed" }
        end
      end

      command
    end

    private def self.execute_command(command : String) : Nil
      Log.info { "Executing: #{command}" }

      # Read all stdin first
      stdin_data = STDIN.gets_to_end

      # Spawn the shell command
      process = Process.new(
        "sh",
        ["-c", command],
        input: Process::Redirect::Pipe,
        output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit
      )

      # Write stdin data to the process
      if !stdin_data.empty?
        process.input.puts(stdin_data)
      end
      process.input.close

      # Wait for the process to complete
      exit_status = process.wait

      # Exit with the same status code
      exit(exit_status.exit_code)
    end
  end
end

Crybot::Crysh.run
