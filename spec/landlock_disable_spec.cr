require "spec"
require "tool_runner"
require "file_utils"

# Test the --no-landlock flag
describe "Landlock Disable Option" do
  it "disables Landlock when flag is set" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join("/home/ralsina", "landlock_disabled_test_#{Random::Secure.hex(8)}.txt")

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Test: Landlock disabled ==="
    puts "Test file: #{test_file}"

    # Create restrictions WITHOUT home directory
    # With Landlock enabled, this should fail
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_read_write("/tmp")

    # Execute with landlock disabled
    result = ToolRunner::Executor.execute(
      command: "echo test > #{test_file}",
      restrictions: restrictions,
      timeout: nil,
      env: nil,
      disable_landlock: true # <-- DISABLE LANDLOCK
    )

    puts "Result: exit=#{result.exit_code}, success=#{result.success?}"

    # With Landlock disabled, the file should be created even though it's not in restrictions
    if File.exists?(test_file)
      puts "PASS: File created (Landlock was disabled)"
      content = File.read(test_file).strip
      puts "Content: #{content}"
      File.delete(test_file)
    else
      puts "FAIL: File not created (Landlock should have been disabled)"
      raise "Landlock disable flag not working"
    end
  end

  it "applies Landlock normally when flag is not set" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join("/home/ralsina", "landlock_normal_test_#{Random::Secure.hex(8)}.txt")

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Test: Landlock normal behavior ==="
    puts "Test file: #{test_file}"

    # Create restrictions WITHOUT home directory
    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_read_write("/tmp")

    # Execute with landlock ENABLED (default)
    result = ToolRunner::Executor.execute(
      command: "echo test > #{test_file}",
      restrictions: restrictions,
      timeout: nil,
      env: nil
      # disable_landlock: false is the default
    )

    puts "Result: exit=#{result.exit_code}, success=#{result.success?}"

    # With Landlock enabled, the file should NOT be created
    if File.exists?(test_file)
      puts "FAIL: File created despite restrictions (Landlock not working)"
      File.delete(test_file)
      raise "Landlock should have blocked this"
    else
      puts "PASS: File not created (Landlock working normally)"
    end
  end

  it "works without Landlock available when disabled" do
    # This test should pass even if Landlock is not available
    test_file = File.join("/tmp", "no_landlock_test_#{Random::Secure.hex(8)}.txt")

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Test: No Landlock available ==="

    # Empty restrictions
    restrictions = ToolRunner::Landlock::Restrictions.new

    # Execute with landlock disabled - should work fine
    result = ToolRunner::Executor.execute(
      command: "echo test > #{test_file}",
      restrictions: restrictions,
      timeout: nil,
      env: nil,
      disable_landlock: true
    )

    puts "Result: exit=#{result.exit_code}, success=#{result.success?}"

    if File.exists?(test_file)
      puts "PASS: File created"
      File.delete(test_file)
    else
      raise "File should have been created"
    end
  end
end
