require "http"
require "json"
require "../agent/cancellation"

module Crybot
  module Providers
    # Async HTTP helper for interruptible HTTP requests
    module AsyncHTTP
      # Perform HTTP POST with cancellation support
      def self.post_with_cancellation(
        url : String,
        headers : HTTP::Headers,
        body : String,
        cancellation_token : Agent::CancellationToken?,
      ) : HTTP::Client::Response
        # Create channels for result and cancellation
        response_channel = Channel(HTTP::Client::Response).new
        cancel_channel = Channel(Nil).new

        # Spawn HTTP request in background fiber
        spawn do
          begin
            # Check for cancellation before making request
            if cancellation_token && cancellation_token.cancelled?
              cancel_channel.send(nil)
              next
            end

            # Make the HTTP request
            response = HTTP::Client.post(url, headers, body)
            response_channel.send(response)
          rescue e : Exception
            # If there was an error, still send to response channel
            # The caller will check the response status
            cancel_channel.send(nil)
          end
        end

        # Wait for either response or cancellation
        select
        when response = response_channel.receive
          # Request completed successfully (or with error)
          response
        when cancel_channel.receive
          # Cancellation was requested
          if cancellation_token
            cancellation_token.cancel
          end
          raise "Request cancelled by user"
        end
      end
    end
  end
end
