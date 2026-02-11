#!/usr/bin/env crystal
# A simple demo of the ToolRunner shard
# Usage: crystal run examples/demo.cr -- [command]

require "../src/tool_runner"

# Get command from args - join multiple args with spaces, or use default
command = ARGV.empty? ? "echo 'Hello from ToolRunner!'" : ARGV.join(" ")

# Check if Landlock is available
if ToolRunner::Landlock.available?
  puts "[ToolRunner] Landlock is available - sandboxing enabled"
else
  puts "[ToolRunner] WARNING: Landlock not available - running without sandboxing"
end

# Create restrictions for common shell operations
restrictions = ToolRunner::Landlock::Restrictions.new
  .add_read_only("/usr")   # For binaries (many shells link to /usr/bin)
  .add_read_only("/bin")   # For shell binaries
  .add_read_only("/lib")   # For shared libraries
  .add_read_only("/lib64") # For shared libraries
  .add_read_only("/dev")   # For /dev/null, /dev/urandom
  .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
  .add_read_write("/tmp") # For temporary files

# Describe the sandbox restrictions
puts "[ToolRunner] Sandbox restrictions:"
puts "[ToolRunner]   READ-ONLY: /usr, /bin, /lib, /lib64, /dev"
puts "[ToolRunner]   READ-WRITE: /tmp"
puts "[ToolRunner]   SPECIAL: /dev/null (read-write)"
puts "[ToolRunner]   BLOCKED: All other paths (including /etc, /home, /root, etc.)"
puts ""

puts "[ToolRunner] Executing: #{command}"
puts "[ToolRunner] ---"

begin
  result = ToolRunner.execute(
    command: command,
    restrictions: restrictions,
    timeout: 30.seconds
  )

  # Print output - labeled by source
  if !result.stdout.empty?
    puts "[ToolRunner] STDOUT:"
    puts result.stdout
  end

  if !result.stderr.empty?
    puts "[ToolRunner] STDERR:"
    puts result.stderr
  end

  puts "[ToolRunner] ---"
  puts "[ToolRunner] Exit code: #{result.exit_code}"
  puts "[ToolRunner] Success: #{result.success?}"

  exit result.exit_code
rescue e : ToolRunner::TimeoutError
  puts "[ToolRunner] ERROR: Command timed out"
  exit 1
rescue e : Exception
  puts "[ToolRunner] ERROR: #{e.message}"
  exit 1
end
