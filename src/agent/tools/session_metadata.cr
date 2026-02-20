require "../../session/manager"
require "../../session/metadata"
require "./base"

module Crybot
  module Agent
    module Tools
      # Update the description of the current chat session
      class UpdateSessionDescriptionTool < Tool
        def name : String
          "update_session_description"
        end

        def description : String
          "Update the description of the current chat session. Use this to summarize what the conversation is about or note important context."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "description" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("A brief description of the conversation (1-2 sentences). What is this chat about? What topics are being discussed?"),
              }),
            }),
            "required" => JSON::Any.new([JSON::Any.new("description")]),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          description = args["description"].as_s

          begin
            # Get current session from agent context
            session_key = Agent.current_session
            return "Error: No active session found" unless session_key

            sessions = Session::Manager.instance
            sessions.update_description(session_key, description)

            "Session description updated."
          rescue e : Exception
            "Failed to update session description: #{e.message}"
          end
        end
      end

      # Update the title of the current chat session
      class UpdateSessionTitleTool < Tool
        def name : String
          "update_session_title"
        end

        def description : String
          "Update the title of the current chat session. Use a short, descriptive title (3-6 words)."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "type"       => JSON::Any.new("object"),
            "properties" => JSON::Any.new({
              "title" => JSON::Any.new({
                "type"        => JSON::Any.new("string"),
                "description" => JSON::Any.new("A short title for the conversation (3-6 words)."),
              }),
            }),
            "required" => JSON::Any.new([JSON::Any.new("title")]),
          }
        end

        def execute(args : Hash(String, JSON::Any)) : String
          title = args["title"].as_s

          begin
            # Get current session from agent context
            session_key = Agent.current_session
            return "Error: No active session found" unless session_key

            sessions = Session::Manager.instance
            sessions.update_title(session_key, title)

            "Session title updated."
          rescue e : Exception
            "Failed to update session title: #{e.message}"
          end
        end
      end
    end
  end
end
