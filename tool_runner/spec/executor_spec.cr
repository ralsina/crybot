require "./spec_helper"

describe ToolRunner::Executor do
  describe ".execute" do
    it "executes a command in isolated context" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      result = ToolRunner::Executor.execute(
        command: "echo test",
        restrictions: restrictions,
        timeout: nil,
        env: nil
      )

      result.success?.should be_true
      result.stdout.should contain("test")
    end

    pending "enforces Landlock restrictions" do
      next unless ToolRunner::Landlock.available?

      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")
      # Note: NOT adding /home, so access should be denied

      begin
        _result = ToolRunner::Executor.execute(
          command: "ls #{ENV.fetch("HOME", "/home")}",
          restrictions: restrictions,
          timeout: 5.seconds,
          env: nil
        )
        # If we got here, the command might have succeeded (e.g., if restrictions don't work as expected)
        # In a real test, we'd verify the behavior
      rescue e : Exception
        # Expected: command might fail due to Landlock restrictions
      end
    end

    it "handles timeout correctly" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      expect_raises(ToolRunner::TimeoutError) do
        ToolRunner::Executor.execute(
          command: "sleep 10",
          restrictions: restrictions,
          timeout: 1.second,
          env: nil
        )
      end
    end
  end

  describe "retry scenario" do
    it "each execution gets a fresh isolated context", tags: ["landlock"] do
      next unless ToolRunner::Landlock.available?

      # First execution with minimal restrictions
      # Note: Need /dev/null for Process.new stdio redirection
      restrictions1 = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      result1 = ToolRunner::Executor.execute(
        command: "echo first",
        restrictions: restrictions1,
        timeout: nil,
        env: nil
      )

      result1.success?.should be_true
      result1.stdout.should contain("first")

      # Second execution with different restrictions
      # This simulates a retry with expanded permissions
      restrictions2 = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_read_only("/etc")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")
        .add_read_write("/var/tmp")

      result2 = ToolRunner::Executor.execute(
        command: "echo second",
        restrictions: restrictions2,
        timeout: nil,
        env: nil
      )

      # Each execution uses a fresh isolated context with its own thread
      # so both should succeed
      result2.success?.should be_true
      result2.stdout.should contain("second")
    end
  end
end
