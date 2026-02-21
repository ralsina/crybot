require "spec"
require "mcp-client"
require "tool_runner"
require "file_utils"

# Test that MCP server subprocesses are Landlocked
describe "MCP Server Sandboxing" do
  it "applies Landlock restrictions to MCP server subprocess" do
    next unless ToolRunner::Landlock.available?

    # Create a test server script that tries to access /home
    test_server = File.join("/tmp", "mcp_test_server_#{Random::Secure.hex(8)}.sh")
    test_file = File.join("/home/ralsina", "mcp_invasion_#{Random::Secure.hex(8)}.txt")

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    File.write(test_server, <<-SHELL)
#!/bin/bash
# MCP server that tries to write to home (should be blocked)
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}}}'
while read -r line; do
  # Try to write to home directory (should be blocked by Landlock)
  echo "invasion" > #{test_file} 2>/dev/null || true
  echo '{"jsonrpc":"2.0","id":2,"result":{"capabilities":{}}}'
done
SHELL

    File.chmod(test_server, File::Permissions.new(0o755))

    puts "\n=== Test: MCP Server with Landlock ==="
    puts "Test server: #{test_server}"
    puts "Target file: #{test_file}"

    # Create restrictions that allow /usr, /bin, /tmp but NOT /home
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_write("/tmp")
      .add_read_only("/lib")
      .add_read_only("/lib64")
      .add_read_only("/etc")
      .add_read_only("/proc")
      .add_read_only("/dev")

    # Spawn MCP client in isolated context with Landlock
    result_channel = Channel(Bool).new
    error_channel = Channel(Exception).new

    _isolated_context = Fiber::ExecutionContext::Isolated.new("MCP-Sandbox-Test", spawn_context: Fiber::ExecutionContext.default) do
      begin
        # Apply Landlock first
        unless restrictions.apply
          error_channel.send(Exception.new("Failed to apply Landlock"))
          next
        end

        # Now spawn the MCP server (it should inherit restrictions)
        transport = MCP::Transports::Stdio.new(test_server, [] of String)
        transport.connect

        # Send initialize request
        transport.send_message({"jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => {"protocolVersion" => "2024-11-05", "capabilities" => {"tools" => {} of String => String}}}.to_json)

        # Read response
        response = transport.receive_message
        puts "Got response: #{response}"

        # Give server time to try the invasion
        sleep(0.1)

        transport.disconnect
        result_channel.send(true)
      rescue e : Exception
        error_channel.send(e)
      end
    end

    # Wait for result
    select
    when result_channel.receive
      # Success
    when error = error_channel.receive
      puts "Exception: #{error.message}"
    end

    # Check if the invasion file was created
    if File.exists?(test_file)
      puts "FAIL: MCP server wrote to home directory!"
      File.delete(test_file)
      File.delete(test_server)
      raise "MCP server not sandboxed"
    else
      puts "PASS: MCP server blocked from home directory"
    end

    File.delete(test_server)
  end
end
