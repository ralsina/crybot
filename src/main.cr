require "./config/loader"
require "./landlock_wrapper"
require "./agent/tool_monitor"
require "./agent/tool_runner_impl"
require "./commands/*"

# Check if we're built with preview_mt for multi-threading support
{% unless flag?(:preview_mt) %}
  puts "=" * 60
  puts "ERROR: crybot must be built with -Dpreview_mt"
  puts "=" * 60
  puts ""
  puts "Crybot requires multi-threading support for the Landlock monitor."
  puts "Please rebuild using:"
  puts ""
  puts "  make build"
  puts ""
  puts "Or manually:"
  puts ""
  puts "  crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context"
  puts ""
  puts "Note: 'shards build' does NOT support these flags."
  puts "Use 'make build' instead."
  puts ""
  exit 1
{% end %}

# Check if we're built with execution_context for Isolated fibers
{% unless flag?(:execution_context) %}
  puts "=" * 60
  puts "ERROR: crybot must be built with -Dexecution_context"
  puts "=" * 60
  puts ""
  puts "Crybot requires execution context support for isolated agent threads."
  puts "Please rebuild using:"
  puts ""
  puts "  make build"
  puts ""
  puts "Or manually:"
  puts ""
  puts "  crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context"
  puts ""
  exit 1
{% end %}

DOC = <<-DOC
Crybot - Crystal-based Personal AI Assistant

Usage:
  crybot onboard
  crybot agent [-m <message>]
  crybot status
  crybot profile
  crybot tool-runner <tool_name> <json_args>
  crybot [-h | --help]

Options:
  -h --help     Show this help message
  -m <message>  Message to send to the agent (non-interactive mode)

Commands:
  onboard       Initialize configuration and workspace
  agent         Interact with the AI agent directly
  status        Show configuration status
  profile       Profile startup performance
  tool-runner   Internal: Execute a tool in a Landlocked subprocess (used by monitor)

Running Crybot:
  When run without arguments, crybot starts all enabled features.
  Enable features in config.yml under the 'features:' section.

Landlock:
  Crybot runs with a monitor that handles access requests via rofi/terminal.
  Tools run in Landlocked subprocesses and request access when needed.
DOC

module Crybot
  # ameba:disable Metrics/CyclomaticComplexity
  def self.run : Nil
    args = ARGV

    # Debug: print arguments
    puts "Args: #{args.inspect}"

    # Show help if requested
    if args.includes?("-h") || args.includes?("--help")
      puts DOC
      return
    end

    cmd = args[0]?

    # Debug: print command
    puts "Command: #{cmd.inspect}"

    case cmd
    when "onboard"
      Commands::Onboard.execute
    when "status"
      Commands::Status.execute
    when "profile"
      Commands::Profile.execute
    when "tool-runner"
      # Internal tool-runner command for Landlocked subprocess execution
      tool_name = args[1]?
      json_args = args[2]?
      if tool_name && json_args
        ToolRunnerImpl.run(tool_name, json_args)
      else
        STDERR.puts "Usage: crybot tool-runner <tool_name> <json_args>"
        exit 1
      end
    when "agent"
      # Note: Landlock disabled for agent because it blocks MCP server subprocess creation
      # MCP servers need to spawn child processes (npx, uvx, etc.)
      # TODO: Consider running only tools in Landlocked subprocesses, not the agent itself
      # LandlockWrapper.ensure_sandbox(args)
      message_idx = args.index("-m")
      message = message_idx ? args[message_idx + 1]? : nil
      Commands::Agent.execute(message)
    when nil
      # Default: start the threaded mode with monitor + agent fibers
      Commands::ThreadedStart.execute
    else
      STDERR.puts "Unknown command: #{cmd.inspect}"
      puts "\n" + DOC
      exit 1
    end
  rescue e : Exception
    puts "Error: #{e.message}"
    puts e.backtrace.join("\n") if ENV["DEBUG"]?
  end
end

Crybot.run
