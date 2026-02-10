module ToolRunner
  # Result of a command execution
  struct ExecutionResult
    getter stdout : String
    getter stderr : String
    getter exit_status : Process::Status
    getter? success : Bool

    def initialize(@stdout : String, @stderr : String, @exit_status : Process::Status)
      @success = @exit_status.success?
    end

    def exit_code : Int
      @exit_status.exit_code
    end
  end

  # Base error class
  class Error < Exception
  end

  # Landlock-specific errors
  class LandlockError < Error
  end

  # Raised when Landlock is not available on the system
  class LandlockNotAvailableError < LandlockError
  end

  # Error during command execution
  class ExecutionError < Error
  end

  # Raised when command execution times out
  class TimeoutError < Error
  end
end
