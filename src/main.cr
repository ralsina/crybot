require "log"
require "./config/loader"
require "./landlock_wrapper"
require "./agent/tool_monitor"
require "./agent/tool_runner_impl"
require "./commands/*"

# Setup logging from environment
Log.setup_from_env

# Check if we're built with preview_mt for multi-threading support
{% unless flag?(:preview_mt) %}
  Log.fatal { "=" * 60 }
  Log.fatal { "ERROR: crybot must be built with -Dpreview_mt" }
  Log.fatal { "=" * 60 }
  Log.fatal { "" }
  Log.fatal { "Crybot requires multi-threading support for the Landlock monitor." }
  Log.fatal { "Please rebuild using:" }
  Log.fatal { "" }
  Log.fatal { "  make build" }
  Log.fatal { "" }
  Log.fatal { "Or manually:" }
  Log.fatal { "" }
  Log.fatal { "  crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context" }
  Log.fatal { "" }
  Log.fatal { "Note: 'shards build' does NOT support these flags." }
  Log.fatal { "Use 'make build' instead." }
  Log.fatal { "" }
  exit 1
{% end %}

# Check if we're built with execution_context for Isolated fibers
{% unless flag?(:execution_context) %}
  Log.fatal { "=" * 60 }
  Log.fatal { "ERROR: crybot must be built with -Dexecution_context" }
  Log.fatal { "=" * 60 }
  Log.fatal { "" }
  Log.fatal { "Crybot requires execution context support for isolated agent threads." }
  Log.fatal { "Please rebuild using:" }
  Log.fatal { "" }
  Log.fatal { "  make build" }
  Log.fatal { "" }
  Log.fatal { "Or manually:" }
  Log.fatal { "" }
  Log.fatal { "  crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context" }
  Log.fatal { "" }
  exit 1
{% end %}

DOC = <<-DOC
Crybot - Crystal-based Personal AI Assistant

Usage:
  crybot onboard
  crybot agent [-m <message>]
  crybot status
  crybot tool-runner <tool_name> <json_args>
  crybot [-h | --help]

Options:
  -h --help     Show this help message
  -m <message>  Message to send to the agent (non-interactive mode)

Commands:
  onboard       Initialize configuration and workspace
  agent         Interact with the AI agent directly
  status        Show configuration status
  tool-runner   Internal: Execute a tool in a Landlocked subprocess (used by monitor)

Running Crybot:
  When run without arguments, crybot starts all enabled features.
  Enable features in config.yml under the 'features:' section.

Landlock:
  Crybot runs with a monitor that handles access requests via rofi/terminal.
  Tools run in Landlocked subprocesses and request access when needed.
DOC

module Crybot
  # Logger for the main Crybot module
  Log = ::Log.for("crybot")

  # ameba:disable Metrics/CyclomaticComplexity
  def self.run : Nil
    args = ARGV

    # Show help if requested
    if args.includes?("-h") || args.includes?("--help")
      Log.info { DOC }
      return
    end

    cmd = args[0]?

    Log.debug { "Running command: #{cmd.inspect}" }

    case cmd
    when "onboard"
      Commands::Onboard.execute
    when "status"
      Commands::Status.execute
    when "tool-runner"
      # Internal tool-runner command for Landlocked subprocess execution
      tool_name = args[1]?
      json_args = args[2]?
      if tool_name && json_args
        ToolRunnerImpl.run(tool_name, json_args)
      else
        Log.error { "Usage: crybot tool-runner <tool_name> <json_args>" }
        exit 1
      end
    when "agent"
      # Note: Landlock disabled for agent because it blocks MCP server subprocess creation
      # MCP servers need to spawn child processes (npx, uvx, etc.)
      # ameba:disable Documentation/DocumentationAdmonition
      # TODO: Consider running only tools in Landlocked subprocesses, not the agent itself
      # LandlockWrapper.ensure_sandbox(args)
      message_idx = args.index("-m")
      message = message_idx ? args[message_idx + 1]? : nil
      Commands::Agent.execute(message)
    when nil
      # Default: start the threaded mode with monitor + agent fibers
      Commands::ThreadedStart.execute
    else
      Log.error { "Unknown command: #{cmd.inspect}" }
      Log.info { "\n" + DOC }
      exit 1
    end
  rescue e : Exception
    Log.error(exception: e) { "Error: #{e.message}" }
    Log.debug(exception: e) { e.backtrace.join("\n") } if ENV["DEBUG"]?
  end
end

Crybot.run
