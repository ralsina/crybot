require "log"
require "json"
require "../../scheduled_tasks/feature"
require "../../scheduled_tasks/config"
require "../../scheduled_tasks/interval_parser"
require "../../scheduled_tasks/registry"
require "../../config/loader"

module Crybot
  module Web
    module Handlers
      class ScheduledTasksHandler
        def feature : ScheduledTasks::Feature
          ScheduledTasks::Registry.instance.feature!
        end

        # List all tasks
        def list_tasks(env) : String
          Log.debug { "[Web/ScheduledTasks] Listing tasks (feature has #{feature.tasks.size} tasks)" }
          tasks = feature.tasks.map(&.to_h)
          {tasks: tasks}.to_json
        end

        # Create a new task
        # ameba:disable Metrics/CyclomaticComplexity
        def create_task(env) : String
          body = env.request.body.try(&.gets_to_end) || ""
          data = Hash(String, JSON::Any).from_json(body)

          # Get required fields
          name = data["name"]?.try(&.as_s?)
          prompt = data["prompt"]?.try(&.as_s?)
          interval = data["interval"]?.try(&.as_s?)
          description = data["description"]?.try(&.as_s?)
          enabled = data["enabled"]?.try(&.as_bool) || true
          forward_to = data["forward_to"]?.try(&.as_s?)
          memory_expiration = data["memory_expiration"]?.try(&.as_s?)

          # Validate required fields
          if name.nil? || name.empty?
            return error_response("Task name is required")
          end

          if prompt.nil? || prompt.empty?
            return error_response("Prompt is required")
          end

          if interval.nil? || interval.empty?
            return error_response("Interval is required")
          end

          # Validate interval format
          unless ScheduledTasks::IntervalParser.valid?(interval)
            return error_response("Invalid interval format. Use formats like: 'hourly', 'daily', 'every 30 minutes', 'every 6 hours'")
          end

          # Generate unique ID
          id = generate_id_from_name(name)

          # Check for duplicate ID
          if feature.get_task(id)
            return error_response("A task with this name already exists")
          end

          # Create task
          task = ScheduledTasks::TaskConfig.new(
            id: id,
            name: name,
            prompt: prompt,
            interval: interval,
            description: description,
            enabled: enabled,
            forward_to: forward_to,
            memory_expiration: memory_expiration
          )

          # Calculate next run time
          task.next_run = ScheduledTasks::IntervalParser.calculate_next_run(interval)

          # Add to feature
          feature.add_task(task)

          {
            success: true,
            message: "Task created successfully",
            task:    task.to_h,
          }.to_json
        rescue e : Exception
          Log.error(exception: e) { "[Web/ScheduledTasks] Failed to create task" }
          error_response("Failed to create task: #{e.message}")
        end

        # Update an existing task
        # ameba:disable Metrics/CyclomaticComplexity
        def update_task(env) : String
          task_id = env.params.url["id"]

          begin
            body = env.request.body.try(&.gets_to_end) || ""
            data = Hash(String, JSON::Any).from_json(body)

            # Get existing task
            existing_task = feature.get_task(task_id)
            if existing_task.nil?
              return error_response("Task not found", 404)
            end

            # Update fields
            name = data["name"]?.try(&.as_s?) || existing_task.name
            prompt = data["prompt"]?.try(&.as_s?) || existing_task.prompt
            interval = data["interval"]?.try(&.as_s?) || existing_task.interval
            description = data["description"]?.try(&.as_s?)
            enabled = data["enabled"]?.try(&.as_bool) || existing_task.enabled?
            forward_to = data["forward_to"]?.try(&.as_s?) || existing_task.forward_to
            memory_expiration = data["memory_expiration"]?.try(&.as_s?)

            # Validate interval if changed
            if interval != existing_task.interval
              unless ScheduledTasks::IntervalParser.valid?(interval)
                return error_response("Invalid interval format")
              end
            end

            # Create updated task preserving last_run and recalculating next_run if interval changed
            task = ScheduledTasks::TaskConfig.new(
              id: task_id,
              name: name,
              prompt: prompt,
              interval: interval,
              description: description,
              enabled: enabled,
              forward_to: forward_to,
              memory_expiration: memory_expiration
            )
            task.last_run = existing_task.last_run

            # Recalculate next run if interval changed
            if interval != existing_task.interval
              task.next_run = ScheduledTasks::IntervalParser.calculate_next_run(interval)
            else
              task.next_run = existing_task.next_run
            end

            # Update in feature
            unless feature.update_task(task_id, task)
              return error_response("Failed to update task")
            end

            {
              success: true,
              message: "Task updated successfully",
              task:    task.to_h,
            }.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/ScheduledTasks] Failed to update task" }
            error_response("Failed to update task: #{e.message}")
          end
        end

        # Delete a task
        def delete_task(env) : String
          task_id = env.params.url["id"]

          unless feature.delete_task(task_id)
            return error_response("Task not found", 404)
          end

          {
            success: true,
            message: "Task deleted successfully",
            id:      task_id,
          }.to_json
        rescue e : Exception
          Log.error(exception: e) { "[Web/ScheduledTasks] Failed to delete task" }
          error_response("Failed to delete task: #{e.message}")
        end

        # Run a task immediately
        def run_task(env) : String
          task_id = env.params.url["id"]

          task = feature.get_task(task_id)
          if task.nil?
            Log.warn { "[Web/ScheduledTasks] Task '#{task_id}' not found" }
            return error_response("Task not found", 404)
          end

          Log.info { "[Web/ScheduledTasks] Manual execution requested for task '#{task.name}' (id: #{task_id})" }

          begin
            # Execute task in a fiber to avoid blocking
            result = feature.execute_task_now(task_id)

            Log.info { "[Web/ScheduledTasks] Task '#{task.name}' execution completed" }

            {
              success: true,
              message: "Task '#{task.name}' executed successfully",
              result:  result,
            }.to_json
          rescue e : Exception
            Log.error(exception: e) { "[Web/ScheduledTasks] Error executing task '#{task.name}'" }
            error_response("Failed to execute task: #{e.message}")
          end
        end

        # Reload tasks from file
        def reload_tasks(env) : String
          Log.info { "[Web/ScheduledTasks] Reloading tasks from file" }
          feature.reload
          {
            success: true,
            message: "Tasks reloaded successfully",
          }.to_json
        rescue e : Exception
          Log.error(exception: e) { "[Web/ScheduledTasks] Error reloading tasks" }
          error_response("Failed to reload tasks: #{e.message}")
        end

        private def error_response(message : String, status : Int32 = 400) : String
          {
            error: message,
          }.to_json
        end

        private def generate_id_from_name(name : String) : String
          # Convert name to a valid ID: lowercase, replace spaces with hyphens, remove special chars
          base_id = name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")

          # Check if ID exists and add suffix if needed
          id = base_id
          counter = 1

          while feature.get_task(id)
            id = "#{base_id}-#{counter}"
            counter += 1
          end

          id
        end
      end
    end
  end
end
