require "./wrapper"

module ToolRunner
  module Landlock
    # Represents a single path rule for Landlock
    struct PathRule
      getter path : String
      getter access_rights : UInt64

      def initialize(@path : String, @access_rights : UInt64)
      end
    end

    # Builds and manages Landlock filesystem restrictions
    class Restrictions
      getter path_rules : Array(PathRule)

      def initialize
        @path_rules = [] of PathRule
      end

      # Add a read-only rule for a path
      def add_read_only(path : String) : self
        add_path(path, ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
      end

      # Add a read-write rule for a path
      def add_read_write(path : String) : self
        add_path(path, ACCESS_FS_RW)
      end

      # Add a path with specific access rights
      def add_path(path : String, access_rights : UInt64) : self
        @path_rules << PathRule.new(path, access_rights)
        self
      end

      # Create default restrictions for crybot
      def self.default_crybot : Restrictions
        home = ENV.fetch("HOME", "")
        return Restrictions.new if home.empty?

        restrictions = Restrictions.new

        # Read-only system directories
        restrictions.add_read_only("/usr")
        restrictions.add_read_only("/bin")
        restrictions.add_read_only("/lib")
        restrictions.add_read_only("/lib64")

        # /dev directory - read-only
        restrictions.add_read_only("/dev")

        # /dev/null specifically - writable
        restrictions.add_path("/dev/null", ACCESS_FS_READ_FILE | ACCESS_FS_WRITE_FILE)

        # /etc - read-only (needed for DNS)
        restrictions.add_read_only("/etc")

        # /proc - read-only (needed by many tools)
        restrictions.add_read_only("/proc")

        # /sys/fs/cgroup - read-only (needed by node)
        restrictions.add_read_only("/sys/fs/cgroup")

        # Home directory - read-only
        restrictions.add_read_only(home)

        # /tmp - read-write
        restrictions.add_read_write("/tmp")

        # .crybot directory structure
        crybot_dir = File.join(home, ".crybot")
        playground = File.join(crybot_dir, "playground")
        workspace = File.join(crybot_dir, "workspace")
        sessions = File.join(crybot_dir, "sessions")
        logs = File.join(crybot_dir, "logs")

        restrictions.add_read_write(playground)
        restrictions.add_read_write(workspace)
        restrictions.add_read_write(sessions)
        restrictions.add_read_write(logs)

        restrictions
      end

      # Apply the restrictions using Landlock
      def apply : Bool
        return false unless Landlock.available?

        # Collect all access rights we want to control
        handled_access = 0_u64
        @path_rules.each do |rule|
          handled_access |= rule.access_rights
        end

        # Create ruleset
        ruleset_fd = Landlock.create_ruleset(handled_access)
        return false unless ruleset_fd && ruleset_fd >= 0

        begin
          # Add each path rule
          @path_rules.each do |rule|
            unless Landlock.add_path_rule(ruleset_fd, rule.path, rule.access_rights)
              STDERR.puts "[Landlock] Failed to add rule for #{rule.path}"
            end
          end

          # Restrict current thread
          Landlock.restrict_self(ruleset_fd)
        ensure
          LibC.close(ruleset_fd) if ruleset_fd && ruleset_fd >= 0
        end
      end
    end
  end
end
