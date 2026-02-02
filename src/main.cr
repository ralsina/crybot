require "docopt"
require "./config/loader"
require "./commands/*"

DOC = <<-DOC
Crybot - Crystal-based Personal AI Assistant

Usage:
  crybot onboard
  crybot agent [-m <message>]
  crybot repl
  crybot status
  crybot gateway
  crybot -h | --help

Options:
  -h --help     Show this help message
  -m <message>  Message to send to the agent (non-interactive mode)

Commands:
  onboard    Initialize configuration and workspace
  agent      Interact with the AI agent directly
  repl       Start an advanced REPL with line editing and history
  status     Show configuration status
  gateway    Start the full service with Telegram integration
DOC

module Crybot
  # ameba:disable Metrics/CyclomaticComplexity
  def self.run : Nil
    begin
      args = Docopt.docopt(DOC)
    rescue e : Docopt::DocoptExit
      puts e.message
      return
    end

    begin
      onboard_val = args["onboard"]
      agent_val = args["agent"]
      repl_val = args["repl"]
      status_val = args["status"]
      gateway_val = args["gateway"]

      if onboard_val.is_a?(Bool) && onboard_val
        Commands::Onboard.execute
      elsif agent_val.is_a?(Bool) && agent_val
        message = args["-m"]
        message_str = message.is_a?(String) ? message : nil
        Commands::Agent.execute(message_str)
      elsif repl_val.is_a?(Bool) && repl_val
        Commands::Repl.start
      elsif status_val.is_a?(Bool) && status_val
        Commands::Status.execute
      elsif gateway_val.is_a?(Bool) && gateway_val
        Commands::Gateway.execute
      end
    rescue e : Exception
      puts "Error: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]?
    end
  end
end

Crybot.run
