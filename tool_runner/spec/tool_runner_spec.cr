require "./spec_helper"

describe ToolRunner do
  describe "VERSION" do
    it "has a version" do
      ToolRunner::VERSION.should match(/^0\.\d+\.\d+$/)
    end
  end

  describe ".execute" do
    it "executes a simple command" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      result = ToolRunner.execute(
        command: "echo hello",
        restrictions: restrictions
      )

      result.success?.should be_true
      result.stdout.should contain("hello")
    end

    it "captures stderr" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      result = ToolRunner.execute(
        command: "sh -c 'echo error >&2'",
        restrictions: restrictions
      )

      result.stderr.should contain("error")
    end

    it "reports exit status correctly" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      result = ToolRunner.execute(
        command: "exit 42",
        restrictions: restrictions
      )

      result.success?.should be_false
      result.exit_code.should eq(42)
    end

    it "supports timeout" do
      restrictions = ToolRunner::Landlock::Restrictions.new
        .add_read_only("/usr")
        .add_read_only("/bin")
        .add_read_only("/dev")
        .add_path("/dev/null", ToolRunner::Landlock::ACCESS_FS_READ_FILE | ToolRunner::Landlock::ACCESS_FS_WRITE_FILE)
        .add_read_write("/tmp")

      expect_raises(ToolRunner::TimeoutError) do
        ToolRunner.execute(
          command: "sleep 10",
          restrictions: restrictions,
          timeout: 100.milliseconds
        )
      end
    end
  end
end
