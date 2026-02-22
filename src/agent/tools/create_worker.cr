require "../tools/base"
require "../../workers/manager"

module Crybot
  module Agent
    module Tools
      # Tool to create worker agents
      class CreateWorker < Tool
        def name : String
          "create_worker"
        end

        def description : String
          "Create a worker agent - a specialized persistent agent with its own instructions. Workers can be addressed by name (e.g., 'Radio, play music')."
        end

        def parameters : Hash(String, JSON::Any)
          {
            "name" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Name of the worker (e.g., 'radio', 'dj', 'assistant')"),
              "required"    => JSON::Any.new(true),
            }),
            "instructions" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("System instructions for the worker - what it should do and how it should behave"),
              "required"    => JSON::Any.new(true),
            }),
          }
        end

        def execute(arguments : Hash(String, JSON::Any)) : String
          name = arguments["name"]?.try(&.as_s)
          instructions = arguments["instructions"]?.try(&.as_s)

          return "Error: 'name' is required" unless name
          return "Error: 'instructions' is required" unless instructions

          # Create the worker
          worker = Workers::Manager.create(name, instructions)

          "Created worker '#{worker.name}'. You can now address it with commands like '#{worker.name}, play music' or '#{worker.name}, switch to jazz'.\n\nThe worker has its own session and will follow these instructions:\n#{worker.instructions}"
        rescue e : Exception
          "Error creating worker: #{e.message}"
        end
      end
    end
  end
end
