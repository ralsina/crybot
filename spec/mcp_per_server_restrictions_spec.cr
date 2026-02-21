require "spec"
require "mcp-client"
require "tool_runner"
require "file_utils"
require "../src/config/schema"

# Test per-MCP server Landlock restrictions
describe "MCP Per-Server Restrictions" do
  it "loads different restrictions for different MCP servers" do
    # Create test configs with different restrictions
    config1 = Crybot::Config::MCPServerConfig.new(
      "playwright",
      "npx -y @executeautomation/playwright",
      nil,
      Crybot::Config::MCPLandlockConfig.new(allowed_paths: ["/tmp/playwright", "/home/ralsina/web-downloads"] of String)
    )

    config2 = Crybot::Config::MCPServerConfig.new(
      "filesystem",
      "npx -y @modelcontextprotocol/server-filesystem",
      nil,
      Crybot::Config::MCPLandlockConfig.new(allowed_paths: ["/tmp", "/home/ralsina/Documents"] of String)
    )

    config1.landlock.should_not be_nil
    if landlock1 = config1.landlock
      landlock1.allowed_paths.should eq ["/tmp/playwright", "/home/ralsina/web-downloads"]
    end
    config2.landlock.should_not be_nil
    if landlock2 = config2.landlock
      landlock2.allowed_paths.should eq ["/tmp", "/home/ralsina/Documents"]
    end
  end

  it "applies specific restrictions when starting MCP server" do
    next unless ToolRunner::Landlock.available?

    test_server = File.join("/tmp", "mcp_restrictions_test_#{Random::Secure.hex(8)}.sh")
    allowed_path = File.join("/tmp", "mcp_allowed_#{Random::Secure.hex(8)}")
    forbidden_path = File.join("/home/ralsina", "mcp_forbidden_#{Random::Secure.hex(8)}.txt")

    # Create allowed directory
    Dir.mkdir(allowed_path)

    # Clean up
    File.delete(forbidden_path) if File.exists?(forbidden_path)

    File.write(test_server, <<-SHELL)
#!/bin/bash
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2024-11-05","capabilities":{"tools":{}}}}'
while read -r line; do
  # Try to write to forbidden path (should be blocked)
  echo "forbidden" > #{forbidden_path} 2>/dev/null || true
  # Try to write to allowed path (should succeed)
  echo "allowed" > #{allowed_path}/test.txt 2>/dev/null || true
  echo '{"jsonrpc":"2.0","id":2,"result":{"capabilities":{}}}'
done
SHELL

    File.chmod(test_server, File::Permissions.new(0o755))

    puts "\n=== Test: MCP with specific restrictions ==="
    puts "Server: #{test_server}"
    puts "Allowed: #{allowed_path}"
    puts "Forbidden: #{forbidden_path}"

    # Create restrictions with only the allowed path
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/lib")
      .add_read_only("/lib64")
      .add_read_only("/etc")
      .add_read_only("/proc")
      .add_read_only("/dev")
      .add_read_write("/tmp")       # Need /tmp for the shell script itself
      .add_read_write(allowed_path) # Only this specific path is allowed for writing

    # Spawn MCP client with specific restrictions
    result_channel = Channel(Bool).new
    error_channel = Channel(Exception).new

    _isolated_context = Fiber::ExecutionContext::Isolated.new("MCP-Restrictions-Test", spawn_context: Fiber::ExecutionContext.default) do
      begin
        # Apply specific Landlock restrictions
        unless restrictions.apply
          error_channel.send(Exception.new("Failed to apply Landlock"))
          next
        end

        # Spawn the MCP server
        transport = MCP::Transports::Stdio.new(test_server, [] of String)
        transport.connect
        transport.send_message({"jsonrpc" => "2.0", "method" => "initialize", "id" => 1, "params" => {"protocolVersion" => "2024-11-05", "capabilities" => {"tools" => {} of String => String}}}.to_json)
        transport.receive_message
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

    # Check results
    if File.exists?(forbidden_path)
      puts "FAIL: MCP server accessed forbidden path!"
      File.delete(forbidden_path)
      File.delete(test_server)
      Dir.delete(allowed_path)
      raise "MCP server not properly restricted"
    else
      puts "PASS: MCP server blocked from forbidden path"
    end

    allowed_file = File.join(allowed_path, "test.txt")
    if File.exists?(allowed_file)
      puts "PASS: MCP server could write to allowed path"
      File.delete(allowed_file)
    else
      puts "FAIL: MCP server could not write to allowed path"
      File.delete(test_server)
      Dir.delete(allowed_path)
      raise "MCP server over-restricted"
    end

    File.delete(test_server)
    Dir.delete(allowed_path)
  end

  it "uses default restrictions when no specific config provided" do
    config = Crybot::Config::MCPServerConfig.new(
      "test-server",
      "npx test-server",
      nil,
      nil # No landlock config - should use defaults
    )

    config.landlock.should be_nil
  end
end
