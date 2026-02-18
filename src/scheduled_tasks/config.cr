require "yaml"

module Crybot
  module ScheduledTasks
    class TaskConfig
      include YAML::Serializable

      property id : String
      property name : String
      property description : String?
      property prompt : String
      property interval : String
      property? enabled : Bool = true
      property last_run : Time?
      property next_run : Time?
      property forward_to : String?        # e.g., "telegram:chat_id" or "web"
      property memory_expiration : String? # e.g., "1 hour", "30 minutes", "none" (nil = no expiration)

      def initialize(@id : String, @name : String, @prompt : String, @interval : String, @description : String? = nil, @enabled : Bool = true, @forward_to : String? = nil, @memory_expiration : String? = nil)
      end

      def to_h : Hash(String, JSON::Any)
        hash = Hash(String, JSON::Any).new
        hash["id"] = JSON::Any.new(@id)
        hash["name"] = JSON::Any.new(@name)
        hash["prompt"] = JSON::Any.new(@prompt)
        hash["interval"] = JSON::Any.new(@interval)
        hash["enabled"] = JSON::Any.new(@enabled)

        hash["description"] = if desc = @description
                                JSON::Any.new(desc)
                              else
                                JSON::Any.new(nil)
                              end

        hash["forward_to"] = if fwd = @forward_to
                               JSON::Any.new(fwd)
                             else
                               JSON::Any.new(nil)
                             end

        hash["memory_expiration"] = if exp = @memory_expiration
                                      JSON::Any.new(exp)
                                    else
                                      JSON::Any.new(nil)
                                    end

        hash["last_run"] = if last = @last_run
                             JSON::Any.new(last.to_s("%Y-%m-%dT%H:%M:%SZ"))
                           else
                             JSON::Any.new(nil)
                           end

        hash["next_run"] = if next_run = @next_run
                             JSON::Any.new(next_run.to_s("%Y-%m-%dT%H:%M:%SZ"))
                           else
                             JSON::Any.new(nil)
                           end

        hash
      end
    end

    class TasksFile
      include YAML::Serializable

      property tasks : Array(TaskConfig) = [] of TaskConfig

      def initialize(@tasks = [] of TaskConfig)
      end
    end
  end
end
