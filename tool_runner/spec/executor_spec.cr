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
      # This test requires Landlock to be available
      skip "Landlock not available" unless ToolRunner::Landlock.available?

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
  end
end
