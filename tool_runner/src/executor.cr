require "process"

module ToolRunner
  # Executes commands in an isolated thread with Landlock restrictions
  class Executor
    # Execute a command with the given restrictions
    def self.execute(
      command : String,
      restrictions : Landlock::Restrictions,
      timeout : Time::Span?,
      env : Hash(String, String)?
    ) : ExecutionResult
      # Create channels for result and error
      result_channel = Channel(ExecutionResult).new
      error_channel = Channel(Exception).new

      # Create isolated execution context
      # The block runs in the isolated context (single thread, dedicated to this task)
      # We need to keep a reference to isolated_context to keep it alive until channels complete
      _isolated_context = Fiber::ExecutionContext::Isolated.new("ToolRunner", spawn_context: Fiber::ExecutionContext.default) do
        begin
          # Apply Landlock restrictions first
          # If restrictions are empty or Landlock is not available, skip silently
          if restrictions.path_rules.empty? || !Landlock.available?
            # No restrictions to apply or Landlock not available - continue without sandboxing
          elsif !restrictions.apply
            error_channel.send(LandlockError.new("Failed to apply Landlock restrictions"))
            next
          end

          # Execute the command
          stdout_io = IO::Memory.new
          stderr_io = IO::Memory.new

          process = Process.new(
            command,
            shell: true,
            output: stdout_io,
            error: stderr_io,
            env: env
          )

          # Wait for process to complete
          status = process.wait

          result = ExecutionResult.new(
            stdout_io.to_s,
            stderr_io.to_s,
            status
          )

          result_channel.send(result)
        rescue e : Exception
          error_channel.send(e)
        end
      end

      # Wait for result with optional timeout
      if timeout
        select
        when result = result_channel.receive
          return result
        when error = error_channel.receive
          raise error
        when timeout(timeout)
          raise TimeoutError.new("Command timed out after #{timeout}")
        end
      else
        # No timeout - wait for result
        select
        when result = result_channel.receive
          return result
        when error = error_channel.receive
          raise error
        end
      end
    end
  end
end
