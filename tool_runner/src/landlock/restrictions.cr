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

    # Represents a single network port rule for Landlock
    struct PortRule
      getter port : UInt16
      getter access_rights : UInt64

      def initialize(@port : UInt16, @access_rights : UInt64)
      end
    end

    # Builds and manages Landlock filesystem and network restrictions
    class Restrictions
      getter path_rules : Array(PathRule)
      getter port_rules : Array(PortRule)

      def initialize
        @path_rules = [] of PathRule
        @port_rules = [] of PortRule
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

      # Add a network port rule
      def add_port(port : UInt16, access_rights : UInt64) : self
        @port_rules << PortRule.new(port, access_rights)
        self
      end

      # Allow TCP connections to a specific port
      def allow_tcp_connect(port : UInt16) : self
        add_port(port, ACCESS_NET_CONNECT_TCP)
      end

      # Allow TCP binding to a specific port
      def allow_tcp_bind(port : UInt16) : self
        add_port(port, ACCESS_NET_BIND_TCP)
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
        handled_access_fs = 0_u64
        @path_rules.each do |rule|
          handled_access_fs |= rule.access_rights
        end

        # Check if we have network rules and if network is supported
        handled_access_net = 0_u64
        has_network_rules = !@port_rules.empty?
        network_supported = Landlock.supports_network?

        if has_network_rules && network_supported
          # Collect network access rights
          @port_rules.each do |rule|
            handled_access_net |= rule.access_rights
          end
        elsif has_network_rules && !network_supported
          STDERR.puts "[Landlock] Network rules requested but kernel doesn't support Landlock network (requires 6.7+)"
        end

        # Create comprehensive ruleset with both filesystem and network
        ruleset_fd = Landlock.create_comprehensive_ruleset(handled_access_fs, handled_access_net)
        return false unless ruleset_fd && ruleset_fd >= 0

        begin
          # Add each path rule
          @path_rules.each do |rule|
            unless Landlock.add_path_rule(ruleset_fd, rule.path, rule.access_rights)
              STDERR.puts "[Landlock] Failed to add rule for #{rule.path}"
            end
          end

          # Add each port rule (if network is supported)
          if has_network_rules && network_supported
            @port_rules.each do |rule|
              unless Landlock.add_port_rule(ruleset_fd, rule.port, rule.access_rights)
                STDERR.puts "[Landlock] Failed to add network rule for port #{rule.port}"
              end
            end
          end

          # Restrict current thread
          Landlock.restrict_self(ruleset_fd)

          true
        ensure
          LibC.close(ruleset_fd) if ruleset_fd && ruleset_fd >= 0
        end
      end
    end
  end
end
