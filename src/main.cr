require "docopt"
require "./config/loader"
require "./commands/*"

DOC = <<-DOC
Crybot - Crystal-based Personal AI Assistant

Usage:
  crybot onboard
  crybot agent [-m <message>]
  crybot status
  crybot profile
  crybot [-h | --help]

Options:
  -h --help     Show this help message
  -m <message>  Message to send to the agent (non-interactive mode)

Commands:
  onboard    Initialize configuration and workspace
  agent      Interact with the AI agent directly
  status     Show configuration status
  profile    Profile startup performance

Running Crybot:
  When run without arguments, crybot starts all enabled features.
  Enable features in config.yml under the 'features:' section.
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
      status_val = args["status"]
      profile_val = args["profile"]

      # Check if any specific command was given (not nil)
      if onboard_val == true
        Commands::Onboard.execute
      elsif agent_val == true
        message = args["-m"]
        message_str = message.is_a?(String) ? message : nil
        Commands::Agent.execute(message_str)
      elsif status_val == true
        Commands::Status.execute
      elsif profile_val == true
        Commands::Profile.execute
      else
        # Default: start the unified command with all enabled features
        Commands::Start.execute
      end
    rescue e : Exception
      puts "Error: #{e.message}"
      puts e.backtrace.join("\n") if ENV["DEBUG"]?
    end
  end
end

Crybot.run
