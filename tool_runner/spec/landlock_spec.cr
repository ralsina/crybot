require "./spec_helper"

describe ToolRunner::Landlock do
  describe ".available?" do
    it "returns a boolean" do
      result = ToolRunner::Landlock.available?
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
  end

  describe "PathRule" do
    it "stores path and access rights" do
      rule = ToolRunner::Landlock::PathRule.new("/tmp", ToolRunner::Landlock::ACCESS_FS_RW)
      rule.path.should eq("/tmp")
      rule.access_rights.should eq(ToolRunner::Landlock::ACCESS_FS_RW)
    end
  end
end
