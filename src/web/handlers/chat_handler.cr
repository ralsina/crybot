require "json"
require "random/secure"
require "../../agent/loop"
require "../../session/manager"

module Crybot
  module Web
    module Handlers
      class ChatHandler
        def initialize(@agent : Agent::Loop, @sessions : Session::Manager)
        end

        # POST /api/chat - Send message and get response (REST endpoint)
        # ameba:disable Metrics/CyclomaticComplexity
        def handle_message(env) : String
          body = env.request.body.try(&.gets_to_end) || ""
          data = JSON.parse(body)

          session_id = data["session_id"]?.try(&.as_s) || generate_session_key
          content = data["content"]?.try(&.as_s) || ""

          if content.empty?
            env.response.status_code = 400
            return {error: "Message content is required"}.to_json
          end

          # Log incoming message
          puts "[Web] [Chat] Session: #{session_id}"
          puts "[Web] [Chat] User: #{content}"

          # Process with agent
          agent_response = @agent.process(session_id, content)

          # Log response (truncated if long)
          response_preview = agent_response.response.size > 200 ? "#{agent_response.response[0..200]}..." : agent_response.response
          puts "[Web] [Chat] Assistant: #{response_preview}"

          # Log tool executions
          agent_response.tool_executions.each do |exec|
            status = exec.success? ? "✓" : "✗"
            puts "[Web] [Tool] #{status} #{exec.tool_name}"
            if exec.tool_name == "exec" || exec.tool_name == "exec_shell"
              args_str = exec.arguments.map { |k, v| "#{k}=#{v}" }.join(" ")
              puts "[Web]       Command: #{args_str}"
              result_preview = exec.result.size > 200 ? "#{exec.result[0..200]}..." : exec.result
              puts "[Web]       Output: #{result_preview}"
            end
          end

          tool_executions_json = agent_response.tool_executions.map(&.to_h).map { |hash| JSON::Any.new(hash) }
          {
            session_id:      session_id,
            content:         agent_response.response,
            tool_executions: JSON::Any.new(tool_executions_json),
            timestamp:       Time.local.to_s("%Y-%m-%dT%H:%M:%S%:z"),
          }.to_json
        rescue e : JSON::ParseException
          env.response.status_code = 400
          {error: "Invalid JSON"}.to_json
        rescue e : Exception
          env.response.status_code = 500
          {error: e.message}.to_json
        end

        private def generate_session_key : String
          "web_#{Random::Secure.hex(16)}"
        end
      end
    end
  end
end
