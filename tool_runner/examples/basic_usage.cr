#!/usr/bin/env crystal
require "../src/tool_runner"

# Check if Landlock is available
if ToolRunner::Landlock.available?
  puts "Landlock is available on this system"
else
  puts "WARNING: Landlock is NOT available on this system"
  puts "Commands will execute without filesystem restrictions"
end

# Create custom restrictions
restrictions = ToolRunner::Landlock::Restrictions.new
  .add_read_only("/usr")
  .add_read_only("/bin")
  .add_read_only("/dev")                                                                                         # Needed for Process.run (opens /dev/null for stdin)
  .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE) # Needed for shell redirection
  .add_read_write("/tmp")

puts "\n=== Example 1: Simple command execution ==="
result = ToolRunner.execute(
  command: "echo 'Hello from ToolRunner!'",
  restrictions: restrictions
)

puts "stdout: #{result.stdout}"
puts "stderr: #{result.stderr}" unless result.stderr.empty?
puts "exit code: #{result.exit_code}"
puts "success: #{result.success?}"

puts "\n=== Example 2: Listing /tmp directory ==="
result = ToolRunner.execute(
  command: "ls -la /tmp",
  restrictions: restrictions
)

puts result.stdout

puts "\n=== Example 3: Command with custom environment ==="
result = ToolRunner.execute(
  command: "echo $FOO",
  restrictions: restrictions,
  env: {"FOO" => "custom value"}
)

puts result.stdout

puts "\n=== Example 4: Command with timeout ==="
begin
  result = ToolRunner.execute(
    command: "sleep 10",
    restrictions: restrictions,
    timeout: 1.second
  )
  puts "Command completed (shouldn't reach here)"
rescue e : ToolRunner::TimeoutError
  puts "Command timed out as expected: #{e.message}"
end

puts "\n=== Example 5: Using default crybot restrictions ==="
home = ENV.fetch("HOME", "")
if home.empty?
  puts "Skipping: HOME not set"
else
  restrictions = ToolRunner::Landlock::Restrictions.default_crybot
  result = ToolRunner.execute(
    command: "echo 'Running with crybot defaults'",
    restrictions: restrictions
  )
  puts result.stdout
end

puts "\nAll examples completed!"
