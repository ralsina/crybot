require "./landlock/wrapper"
require "./landlock/restrictions"
require "./result"
require "./executor"

module ToolRunner
  VERSION = "0.1.0"

  # Execute a command with Landlock restrictions
  #
  # ```
  # restrictions = ToolRunner::Landlock::Restrictions.new
  #   .add_read_only("/usr")
  #   .add_read_write("/tmp")
  #
  # result = ToolRunner.execute(
  #   command: "ls -la /tmp",
  #   restrictions: restrictions,
  #   timeout: 30.seconds
  # )
  #
  # puts result.stdout
  # ```
  def self.execute(
    command : String,
    restrictions : Landlock::Restrictions,
    timeout : Time::Span? = nil,
    env : Hash(String, String)? = nil,
  ) : ExecutionResult
    Executor.execute(command, restrictions, timeout, env)
  end
end
