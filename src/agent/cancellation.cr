require "log"

module Crybot
  module Agent
    Log = ::Log.for("crybot.agent.cancellation")

    # Cancellation token for interruptible operations
    class CancellationToken
      getter? cancelled : Bool

      def initialize
        @cancelled = false
        @mutex = Mutex.new
      end

      # Cancel the operation
      def cancel
        @mutex.synchronize do
          @cancelled = true
        end
        Log.info { "[CancellationToken] Operation cancelled" }
      end

      # Check if cancelled
      def cancelled?
        @mutex.synchronize do
          @cancelled
        end
      end

      # Reset the token for reuse
      def reset
        @mutex.synchronize do
          @cancelled = false
        end
      end
    end

    # Global cancellation manager for active operations
    class CancellationManager
      @@current_token : CancellationToken?
      @@mutex = Mutex.new

      # Get or create the current cancellation token
      def self.current_token : CancellationToken
        @@mutex.synchronize do
          @@current_token ||= CancellationToken.new
        end
      end

      # Cancel the current operation
      def self.cancel_current
        @@mutex.synchronize do
          if token = @@current_token
            token.cancel
          end
        end
      end

      # Reset for new operation
      def self.reset
        @@mutex.synchronize do
          @@current_token = CancellationToken.new
        end
      end

      # Check if current operation is cancelled
      def self.cancelled?
        @@mutex.synchronize do
          if token = @@current_token
            token.cancelled?
          else
            false
          end
        end
      end
    end
  end
end
