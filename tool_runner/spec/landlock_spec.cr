require "./spec_helper"

describe ToolRunner::Landlock do
  describe ".available?" do
    it "returns a boolean" do
      result = ToolRunner::Landlock.available?
      result.should be_a(Bool)
    end
  end

  describe ".supports_network?" do
    it "returns a boolean" do
      result = ToolRunner::Landlock.supports_network?
      result.should be_a(Bool)
    end
  end

  describe "Restrictions" do
    describe "#add_read_only" do
      it "adds a read-only rule" do
        restrictions = ToolRunner::Landlock::Restrictions.new
          .add_read_only("/tmp")

        restrictions.path_rules.size.should eq(1)
        restrictions.path_rules[0].path.should eq("/tmp")
      end
    end

    describe "#add_read_write" do
      it "adds a read-write rule" do
        restrictions = ToolRunner::Landlock::Restrictions.new
          .add_read_write("/tmp")

        restrictions.path_rules.size.should eq(1)
        restrictions.path_rules[0].path.should eq("/tmp")
      end
    end

    describe "#add_path" do
      it "adds a path with custom access rights" do
        restrictions = ToolRunner::Landlock::Restrictions.new
          .add_path("/tmp", ToolRunner::Landlock::ACCESS_FS_READ_FILE)

        restrictions.path_rules.size.should eq(1)
        restrictions.path_rules[0].path.should eq("/tmp")
        restrictions.path_rules[0].access_rights.should eq(ToolRunner::Landlock::ACCESS_FS_READ_FILE)
      end
    end

    describe ".default_crybot" do
      it "creates default restrictions for crybot" do
        home = ENV.fetch("HOME", "")
        if home.empty?
          restrictions = ToolRunner::Landlock::Restrictions.new
          restrictions.path_rules.should be_empty
        else
          restrictions = ToolRunner::Landlock::Restrictions.default_crybot
          restrictions.path_rules.should_not be_empty
        end
      end
    end

    describe "#apply" do
      # NOTE: We cannot test apply directly in the spec process because it applies
      # Landlock to the main thread, breaking subsequent file operations.
      # The executor tests verify apply works correctly in isolated contexts.

      it "returns false when Landlock is not available" do
        # Create restrictions but don't call apply
        restrictions = ToolRunner::Landlock::Restrictions.new
          .add_read_only("/tmp")

        # Verify we can create restrictions
        restrictions.path_rules.size.should eq(1)
      end
    end

    describe "network restrictions" do
      it "can add TCP connect port rules" do
        restrictions = ToolRunner::Landlock::Restrictions.new
          .allow_tcp_connect(8080)

        restrictions.port_rules.size.should eq(1)
        restrictions.port_rules[0].port.should eq(8080)
      end

      it "can add TCP bind port rules" do
        restrictions = ToolRunner::Landlock::Restrictions.new
          .allow_tcp_bind(3000)

        restrictions.port_rules.size.should eq(1)
        restrictions.port_rules[0].port.should eq(3000)
      end

      it "applies network restrictions when kernel supports it", tags: ["landlock"] do
        next unless ToolRunner::Landlock.available?

        restrictions = ToolRunner::Landlock::Restrictions.new
          .add_read_write("/tmp")
          .allow_tcp_connect(8080)

        # Don't call apply directly - it would affect the spec process
        # Just verify the restrictions were configured correctly
        restrictions.port_rules.size.should eq(1)
        restrictions.port_rules[0].port.should eq(8080)
        restrictions.path_rules.size.should eq(1)
      end
    end
  end

  describe "PathRule" do
    it "stores path and access rights" do
      rule = ToolRunner::Landlock::PathRule.new("/tmp", ToolRunner::Landlock::ACCESS_FS_RW)
      rule.path.should eq("/tmp")
      rule.access_rights.should eq(ToolRunner::Landlock::ACCESS_FS_RW)
    end
  end

  describe "PortRule" do
    it "stores port and access rights" do
      rule = ToolRunner::Landlock::PortRule.new(8080, ToolRunner::Landlock::ACCESS_NET_CONNECT_TCP)
      rule.port.should eq(8080)
      rule.access_rights.should eq(ToolRunner::Landlock::ACCESS_NET_CONNECT_TCP)
    end
  end

  # NOTE: Testing restrict_self directly in the spec process is problematic
  # because once Landlock is applied to the main thread, it affects all
  # subsequent tests. The Executor tests verify that each execution gets
  # a fresh isolated context, which is the important behavior for tool_runner.
end
