require "spec"
require "file_utils"
require "tool_runner"

# Test the retry scenario: tool execution with Landlock denial and permission grant
describe "Landlock Retry Scenario" do
  it "allows retry after granting permission via rofi" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join(ENV.fetch("HOME", ""), "landlock_retry_test_#{Random::Secure.hex(8)}.txt")
    parent_dir = File.dirname(test_file)

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Test: Retry after permission grant ==="
    puts "Test file: #{test_file}"
    puts "Parent dir: #{parent_dir}"

    # First attempt: restrictions WITHOUT home directory
    # Only allow specific paths, not home
    restrictions1 = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
      .add_read_write("/tmp")

    puts "\n--- Attempt 1: Without home directory access ---"
    puts "Restrictions: / (deny all), /usr, /bin, /dev, /tmp (NO home)"

    # Try to write to home - should be blocked
    ToolRunner::Executor.execute(
      command: "echo test > #{test_file}",
      restrictions: restrictions1,
      timeout: nil,
      env: nil
    )

    if File.exists?(test_file)
      puts "ERROR: File created despite restrictions!"
      File.delete(test_file)
      raise "Landlock not working"
    else
      puts "OK: File not created (as expected)"
    end

    # Now simulate granting permission: create NEW restrictions with home added
    puts "\n--- Simulating: User granted permission via rofi ---"
    puts "Adding home directory to restrictions..."

    restrictions2 = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")
      .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
      .add_read_write("/tmp")
      .add_read_write(parent_dir) # <-- GRANTED PERMISSION

    puts "Restrictions: /usr, /bin, /dev, /tmp, #{parent_dir} (HOME ADDED)"

    # Second attempt: restrictions WITH home directory
    puts "\n--- Attempt 2: With home directory access ---"

    puts "DEBUG: restrictions2 has #{restrictions2.path_rules.size} rules"
    restrictions2.path_rules.each do |rule|
      puts "DEBUG:  - #{rule.path} (rights: #{rule.access_rights})"
    end

    # Add more paths that Ruby might need
    restrictions2.add_read_only("/lib")
    restrictions2.add_read_only("/lib64")
    restrictions2.add_read_only("/usr/lib")

    puts "DEBUG: Added /lib, /lib64, /usr/lib for Ruby"

    # Verify the home dir is actually in the restrictions
    has_home = restrictions2.path_rules.any? { |rule| test_file.starts_with?(rule.path) }
    puts "DEBUG: Test file #{test_file} starts with any restricted path: #{has_home}"

    # Try with a simple command that writes to /dev/null first
    # to verify the isolation context itself works
    test_result = ToolRunner::Executor.execute(
      command: "ls /home/ralsina",
      restrictions: restrictions2,
      timeout: nil,
      env: nil
    )

    puts "DEBUG: ls /home/ralsina result:"
    puts "  success: #{test_result.success?}"
    puts "  exit_code: #{test_result.exit_code}"
    puts "  stdout: #{test_result.stdout}"

    # Now try to create the file
    # Use /usr/bin/ruby explicitly
    result2 = ToolRunner::Executor.execute(
      command: "/usr/bin/ruby -e 'File.write(\"#{test_file}\", \"test2\")'",
      restrictions: restrictions2,
      timeout: nil,
      env: nil
    )

    puts "DEBUG: Ruby execution result:"
    puts "  success: #{result2.success?}"
    puts "  exit_code: #{result2.exit_code}"
    puts "  stdout: #{result2.stdout}"
    puts "  stderr: #{result2.stderr}"

    # Try writing to /tmp instead (which we know is allowed)
    tmp_file = File.join("/tmp", "landlock_tmp_#{Random::Secure.hex(8)}.txt")
    result3 = ToolRunner::Executor.execute(
      command: "/usr/bin/ruby -e 'File.write(\"#{tmp_file}\", \"tmp_test\")'",
      restrictions: restrictions2,
      timeout: nil,
      env: nil
    )

    puts "\nDEBUG: Write to /tmp result:"
    puts "  success: #{result3.success?}"
    puts "  exit_code: #{result3.exit_code}"
    puts "  stderr: #{result3.stderr}"

    if File.exists?(tmp_file)
      puts "  File created: #{tmp_file}"
      File.delete(tmp_file)
    else
      puts "  File NOT created"
    end

    # Try a simple echo without file operations
    result4 = ToolRunner::Executor.execute(
      command: "echo 'hello from landlock'",
      restrictions: restrictions2,
      timeout: nil,
      env: nil
    )

    puts "\nDEBUG: Simple echo result:"
    puts "  success: #{result4.success?}"
    puts "  stdout: #{result4.stdout.strip}"

    if File.exists?(test_file)
      puts "OK: File created with granted permission"
      content = File.read(test_file)
      puts "Content: #{content.strip}"
      File.delete(test_file)
    else
      puts "ERROR: File not created even with permission granted!"
      puts "This is the bug we need to fix"
      raise "Retry after permission grant failed"
    end
  end

  it "simulates the exact tool_monitor retry flow" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join(ENV.fetch("HOME", ""), "landlock_flow_test_#{Random::Secure.hex(8)}.txt")
    parent_dir = File.dirname(test_file)

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Simulating tool_monitor flow ==="

    # This simulates what tool_monitor does:
    # 1. Create initial restrictions (without the target path)
    restrictions = ToolRunner::Landlock::Restrictions.default_crybot

    puts "\nInitial restrictions from default_crybot:"
    puts "  - #{restrictions.path_rules.size} path rules"
    restrictions.path_rules.each do |rule|
      puts "  - #{rule.path} (rights: #{rule.access_rights})"
    end

    # Check if home is in default restrictions
    home_in_default = restrictions.path_rules.any? do |rule|
      test_file.starts_with?(rule.path)
    end

    if home_in_default
      puts "Home is already in default restrictions - test invalid"
      next # skip "Home directory already in default_crybot restrictions"
    end

    # 2. First execution attempt (should fail)
    puts "\n--- First execution attempt (should fail) ---"

    begin
      ToolRunner::Executor.execute(
        command: "echo attempt1 > #{test_file}",
        restrictions: restrictions,
        timeout: nil,
        env: nil
      )

      if File.exists?(test_file)
        puts "WARNING: File created on first attempt (home might be in default restrictions)"
        File.delete(test_file)
        next # skip "Test setup invalid - home already accessible"
      else
        puts "OK: First attempt failed as expected"
      end
    rescue e : Exception
      puts "First attempt raised exception: #{e.class.name}: #{e.message}"
    end

    # 3. Simulate permission grant (add path to restrictions)
    puts "\n--- Simulating permission grant (add path to restrictions) ---"

    original_count = restrictions.path_rules.size
    restrictions.add_read_write(parent_dir)

    puts "Added #{parent_dir} to restrictions"
    puts "Path rules before: #{original_count}, after: #{restrictions.path_rules.size}"

    # 4. Second execution attempt (should succeed)
    puts "\n--- Second execution attempt (should succeed) ---"

    begin
      result2 = ToolRunner::Executor.execute(
        command: "echo attempt2 > #{test_file}",
        restrictions: restrictions,
        timeout: nil,
        env: nil
      )

      if File.exists?(test_file)
        puts "OK: Second attempt succeeded - file created"
        File.delete(test_file)
      else
        puts "ERROR: Second attempt failed - file NOT created"
        puts "Exit status: #{result2.exit_status}"
        puts "Stdout: #{result2.stdout}"
        puts "Stderr: #{result2.stderr}"
        raise "Retry after granting permission failed"
      end
    rescue e : Exception
      puts "ERROR: Second attempt raised exception: #{e.class.name}: #{e.message}"
      raise e
    end
  end

  it "tests multiple retries with expanding permissions" do
    next unless ToolRunner::Landlock.available?

    test_file = File.join("/tmp", "multi_retry_#{Random::Secure.hex(8)}.txt")

    # Clean up
    File.delete(test_file) if File.exists?(test_file)

    puts "\n=== Testing multiple retries ==="

    restrictions = ToolRunner::Landlock::Restrictions.new
      .add_read_only("/usr")
      .add_read_only("/bin")
      .add_read_only("/dev")

    max_attempts = 3

    (1..max_attempts).each do |attempt|
      puts "\n--- Attempt #{attempt} ---"

      # For this test, add /tmp on attempt 2
      if attempt == 2
        puts "Adding /tmp to restrictions (simulating permission grant)"
        restrictions.add_read_write("/tmp")
      end

      begin
        ToolRunner::Executor.execute(
          command: "echo attempt#{attempt} > #{test_file}",
          restrictions: restrictions,
          timeout: nil,
          env: nil
        )

        if File.exists?(test_file)
          puts "OK: Attempt #{attempt} succeeded"
          File.delete(test_file)
          break
        else
          puts "Attempt #{attempt} failed - file not created"
        end
      rescue e : Exception
        puts "Attempt #{attempt} raised exception: #{e.class.name}"
      end
    end
  end
end
