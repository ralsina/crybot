require "log"

module Crybot
  module Workers
    # Worker agent state and metadata
    struct Worker
      include JSON::Serializable

      property name : String
      property instructions : String
      property status : Status
      property created_at : Time

      enum Status
        Idle
        Running
        Paused

        def to_s : String
          to_s.downcase
        end
      end

      def initialize(@name : String, @instructions : String)
        @status = Status::Idle
        @created_at = Time.utc
      end

      # Get the session key for this worker
      def session_key : String
        "worker:#{@name}"
      end

      # Check if this worker matches a command
      def matches_command?(command : String) : Bool
        # Match patterns like "WorkerName, do something" or "WorkerName: do something"
        pattern = /^#{Regex.escape(@name)}[,:\s]+(.*)/i
        !!command.match(pattern)
      end

      # Extract the actual command from a message addressed to this worker
      def extract_command(message : String) : String?
        pattern = /^#{Regex.escape(@name)}[,:\s]+(.*)/i
        match = message.match(pattern)
        match[1]? if match
      end
    end
  end
end
