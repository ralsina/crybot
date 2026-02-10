# ToolRunner

Sandboxed command execution using Linux Landlock and Crystal's `ExecutionContext::Isolated`.

## Features

- Thread isolation using Crystal's `ExecutionContext::Isolated`
- Filesystem access control via Linux Landlock (kernel 5.13+)
- Captures stdout, stderr, and exit status
- Configurable timeout support
- No root privileges required

## Requirements

- Linux kernel 5.13+ (for Landlock support)
- Crystal 1.13.0+ compiled with `-Dpreview_mt -Dexecution_context`

## Quick Test / Demo

Run the included demo to see ToolRunner in action:

```bash
cd ~/code/crybot/tool_runner
./demo 'echo hello'
./demo 'ls -la /tmp'
./demo 'cat /etc/passwd'  # Will be blocked by Landlock
```

Or directly with Crystal:

```bash
cd ~/code/crybot/tool_runner
crystal run examples/demo.cr -Dpreview_mt -Dexecution_context -- "echo hello"
```

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  tool_runner:
    path: ~/code/crybot/tool_runner
```

## Usage

```crystal
require "tool_runner"

# Create restrictions
restrictions = ToolRunner::Landlock::Restrictions.new
  .add_read_only("/usr")
  .add_read_only("/bin")
  .add_read_only("/dev")
  .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
  .add_read_write("/tmp")

# Execute a command
result = ToolRunner.execute(
  command: "ls -la /tmp",
  restrictions: restrictions,
  timeout: 30.seconds
)

puts result.stdout
puts result.stderr unless result.stderr.empty?
puts "Exit status: #{result.exit_code}"
puts "Success: #{result.success?}"
```

## Building

The shard requires specific Crystal compilation flags:

```bash
crystal build src/tool_runner.cr -o bin/tool_runner -Dpreview_mt -Dexecution_context
```

## License

MIT License - see LICENSE file for details.
