require "spec"
require "../src/tool_runner"

Spec.before_suite do
  # Check if Landlock is available
  unless ToolRunner::Landlock.available?
    puts "\nWARNING: Landlock is not available on this system. Some tests will be skipped."
  end
end
