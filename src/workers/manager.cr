require "./worker"
require "log"

module Crybot
  module Workers
    # Manages worker agents - specialized persistent agents
    class Manager
      @@workers = Hash(String, Worker).new
      @@mutex = Mutex.new

      Log = ::Log.for("crybot.workers")

      # Create a new worker
      def self.create(name : String, instructions : String) : Worker
        @@mutex.synchronize do
          worker = Worker.new(name, instructions)
          @@workers[name.downcase] = worker
          Log.info { "Created worker '#{name}'" }
          worker
        end
      end

      # Get a worker by name (case-insensitive)
      def self.get(name : String) : Worker?
        @@workers[name.downcase]?
      end

      # List all workers
      def self.all : Array(Worker)
        @@mutex.synchronize do
          @@workers.values
        end
      end

      # Delete a worker
      def self.delete(name : String) : Bool
        @@mutex.synchronize do
          if @@workers.delete(name.downcase)
            Log.info { "Deleted worker '#{name}'" }
            true
          else
            false
          end
        end
      end

      # Find a worker that matches the given command
      def self.find_matching_worker(command : String) : Worker?
        @@mutex.synchronize do
          @@workers.values.find do |worker|
            worker.matches_command?(command)
          end
        end
      end

      # Clear all workers (mainly for testing)
      def self.clear : Nil
        @@mutex.synchronize do
          @@workers.clear
        end
      end
    end
  end
end
