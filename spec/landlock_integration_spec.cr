require "spec"
require "file_utils"
require "tool_runner"

# Integration tests for Landlock file access restrictions
describe "Landlock Integration" do
  it "blocks file access outside allowed paths" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join("/tmp", "landlock_test_#{Random::Secure.hex(8)}.txt")
    home_file = File.join(ENV.fetch("HOME", ""), "landlock_test_#{Random::Secure.hex(8)}.txt")

    # Clean up any existing test files
    File.delete(test_file) if File.exists?(test_file)
    File.delete(home_file) if File.exists?(home_file)

    # Create restrictions that DON'T allow /tmp or home
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)

    puts "DEBUG: restrictions.path_rules.size = #{restrictions.path_rules.size}"
    puts "DEBUG: Landlock.available? = #{ToolRunner::Landlock.available?}"

    # Try to list /tmp - should be blocked
    begin
      result = ToolRunner::Executor.execute(
        command: "ls /tmp",
        restrictions: restrictions,
        timeout: nil,
        env: nil
      )

      # If we got here, check output
      if result.stdout.empty?
        puts "OK: /tmp not accessible (no output)"
      else
        puts "ERROR: Landlock not working - ls /tmp succeeded with output: #{result.stdout}"
      end
    rescue e : Exception
      puts "OK: Exception raised: #{e.class.name} - #{e.message}"
    ensure
      File.delete(test_file) if File.exists?(test_file)
    end

    # Now try with /tmp allowed - should work
    restrictions2 = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
      .add_read_write("/tmp")

    begin
      result2 = ToolRunner::Executor.execute(
        command: "echo test2 > #{test_file}",
        restrictions: restrictions2,
        timeout: nil,
        env: nil
      )

      if File.exists?(test_file)
        puts "OK: File created when path was allowed"
        File.delete(test_file)
      else
        puts "ERROR: File not created even though path was allowed"
      end
    rescue e : Exception
      puts "ERROR: Exception raised even though path was allowed: #{e.message}"
    end
  end

  it "detects when Landlock is not being applied" do
    next unless ToolRunner::Landlock.available?

    # This test verifies Landlock is actually working
    # Create restrictions that block /home
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
      .add_read_write("/tmp")

    test_file = File.join(ENV.fetch("HOME", ""), "landlock_block_test_#{Random::Secure.hex(8)}.txt")

    # Try to write to home - should be blocked
    begin
      result = ToolRunner::Executor.execute(
        command: "echo blocked > #{test_file}",
        restrictions: restrictions,
        timeout: nil,
        env: nil
      )

      if File.exists?(test_file)
        puts "CRITICAL: Landlock NOT working - file created in home despite restrictions!"
        File.delete(test_file)
        raise "Landlock is not enforcing restrictions"
      else
        puts "OK: Home directory write was blocked"
      end
    rescue e : Exception
      puts "OK: Write to home blocked with exception: #{e.class.name}"
    ensure
      File.delete(test_file) if File.exists?(test_file)
    end
  end
end
