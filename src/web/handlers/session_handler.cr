require "json"
require "../../session/manager"

module Crybot
  module Web
    module Handlers
      class SessionHandler
        def initialize(@sessions : Session::Manager)
        end

        # GET /api/sessions - List all sessions
        def list_sessions(env) : String
          sessions_with_metadata = @sessions.list_sessions_with_metadata
          {
            sessions: sessions_with_metadata,
            count:    sessions_with_metadata.size,
          }.to_json
        end

        # GET /api/sessions/:id - Get session messages
        def get_session(env) : String
          session_id = env.params.url["id"]
          messages = @sessions.get_or_create(session_id)
          metadata = @sessions.get_metadata(session_id)

          {
            session_id:  session_id,
            title:       metadata.title,
            description: metadata.description,
            messages:    messages.map do |msg|
              msg_hash = Hash(String, JSON::Any).new
              msg_hash["role"] = JSON::Any.new(msg.role)
              msg_hash["content"] = JSON::Any.new(msg.content) if msg.content

              # Include tool_calls if present
              calls = msg.tool_calls
              if calls && !calls.empty?
                msg_hash["tool_calls"] = JSON::Any.new(calls.map(&.to_h).map { |hash| JSON::Any.new(hash) })
              end

              # Include tool_call_id if present
              if tool_id = msg.tool_call_id
                msg_hash["tool_call_id"] = JSON::Any.new(tool_id)
              end

              msg_hash
            end,
          }.to_json
        end

        # DELETE /api/sessions/:id - Delete session
        def delete_session(env) : String
          session_id = env.params.url["id"]
          @sessions.delete(session_id)
          env.response.status_code = 200
          {success: true}.to_json
        end

        # PATCH /api/sessions/:id/metadata - Update session metadata
        def update_metadata(env) : String
          session_id = env.params.url["id"]
          metadata = @sessions.get_metadata(session_id)

          # Parse request body
          body = env.request.body
          return {error: "No body provided"}.to_json unless body

          begin
            data = JSON.parse(body.gets_to_end)

            if title = data["title"]?.try(&.as_s?)
              metadata.update_title(title)
            end

            if description = data["description"]?.try(&.as_s?)
              metadata.update_description(description)
            end

            @sessions.save_metadata(session_id, metadata)

            {
              success:     true,
              title:       metadata.title,
              description: metadata.description,
            }.to_json
          rescue e : Exception
            env.response.status_code = 400
            {error: "Invalid JSON: #{e.message}"}.to_json
          end
        end
      end
    end
  end
end
