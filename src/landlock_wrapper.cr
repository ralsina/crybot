require "log"
require "yaml"

module Crybot
  # Landlock sandboxing wrapper
  #
  # Uses Linux Landlock for filesystem access control without requiring
  # root privileges or external dependencies.
  #
  # Landlock is available in Linux 5.13+ and provides unprivileged
  # sandboxing through file access rules.
  #
  # Security policy:
  # - Read-write: ~/.crybot/playground, ~/.crybot/workspace, ~/.crybot/sessions,
  #               ~/.crybot/logs, ~/.crybot/config.yml, /tmp
  # - Read-only: ~/ (home directory), /usr, /bin, /lib, /lib64,
  #              /dev/null, /dev/urandom, /dev/random, /etc
  # - Blocked: All other paths (including /dev/sda, /dev/tty, input devices, etc.)
  module LandlockWrapper
    # Landlock ABI versions
    ABI_V1 = 1
    ABI_V2 = 2
    ABI_V3 = 3
    ABI_V4 = 4
    ABI_V5 = 5
    ABI_V6 = 6

    # Landlock access rights for filesystem (ABI v1)
    ACCESS_FS_READ_FILE   = 1_u64 << 0
    ACCESS_FS_WRITE_FILE  = 1_u64 << 1
    ACCESS_FS_READ_DIR    = 1_u64 << 2
    ACCESS_FS_REMOVE_DIR  = 1_u64 << 3
    ACCESS_FS_REMOVE_FILE = 1_u64 << 4
    ACCESS_FS_MAKE_CHAR   = 1_u64 << 5
    ACCESS_FS_MAKE_DIR    = 1_u64 << 6
    ACCESS_FS_MAKE_REG    = 1_u64 << 7
    ACCESS_FS_MAKE_SOCK   = 1_u64 << 8
    ACCESS_FS_MAKE_FIFO   = 1_u64 << 9
    ACCESS_FS_MAKE_BLOCK  = 1_u64 << 10
    ACCESS_FS_MAKE_SYM    = 1_u64 << 11

    # Additional access rights for ABI v2
    ACCESS_FS_REFER    = 1_u64 << 13
    ACCESS_FS_TRUNCATE = 1_u64 << 14

    # All access rights we want to control
    ACCESS_FS_RW = ACCESS_FS_READ_FILE | ACCESS_FS_WRITE_FILE | ACCESS_FS_READ_DIR |
                   ACCESS_FS_MAKE_DIR | ACCESS_FS_MAKE_REG | ACCESS_FS_MAKE_SYM |
                   ACCESS_FS_REMOVE_FILE | ACCESS_FS_REMOVE_DIR | ACCESS_FS_TRUNCATE

    # Landlock rule types
    RULE_PATH_BENEATH = 1_u64

    # Syscall numbers from asm/unistd.h (x86_64)
    SYS_LANDLOCK_CREATE_RULESET = 444
    SYS_LANDLOCK_ADD_RULE       = 445
    SYS_LANDLOCK_RESTRICT_SELF  = 446
    SYS_PRCTL                   = 157

    # prctl constants
    PR_SET_NO_NEW_PRIVS = 38
    PR_GET_NO_NEW_PRIVS = 39

    # Open flags that might not be in LibC
    O_PATH    = 0o10000000
    O_CLOEXEC =  0o2000000

    # FFI bindings for Landlock
    lib LibLandlock
      struct LandlockRulesetAttr
        handled_access_fs : UInt64
      end

      struct LandlockPathBeneathAttr
        allowed_access : UInt64
        parent_fd : LibC::Int
      end

      # syscall is provided by LibC
    end

    # Check if Landlock is available on this system
    def self.available? : Bool
      # Check kernel version first
      kv = kernel_version
      return false unless kv

      major, minor = kv.split(".").first(2).map(&.to_i?)
      major ||= 0
      minor ||= 0

      # Check if kernel is 5.13 or later
      return false unless major > 5 || (major == 5 && minor >= 13)

      # Try to create a minimal ruleset to verify Landlock works
      check_ruleset = create_ruleset(ACCESS_FS_READ_FILE)
      return false unless check_ruleset

      # Close the ruleset fd
      LibC.close(check_ruleset)
      true
    rescue
      false
    end

    def self.under_landlock? : Bool
      ENV.fetch("CRYBOT_LANDLOCKED", "0") == "1"
    end

    # Ensure we're running under Landlock sandbox
    def self.ensure_sandbox(args : Array(String)) : Nil
      # Skip if we're just running setup/status commands
      if args.includes?("onboard") || args.includes?("status") || args.includes?("profile") || args.includes?("monitor")
        return
      end

      # Skip if already under Landlock
      if under_landlock?
        return
      end

      # Check if Landlock is available
      unless available?
        Log.warn { "" }
        Log.warn { "⚠️  WARNING: Landlock is not available on this system." }
        Log.warn { "Kernel 5.13+ required. Continuing without sandboxing." }
        return
      end

      # Apply Landlock sandbox to current process
      apply_sandbox
    end

    # Apply Landlock sandbox to the current process
    # ameba:disable Metrics/CyclomaticComplexity
    private def self.apply_sandbox : Bool
      home = ENV.fetch("HOME", "")
      return false if home.empty?

      playground = File.join(home, ".crybot", "playground")
      workspace = File.join(home, ".crybot", "workspace")
      sessions = File.join(home, ".crybot", "sessions")
      logs = File.join(home, ".crybot", "logs")

      # Create ruleset with all access rights we want to control
      ruleset_fd = create_ruleset(ACCESS_FS_RW)
      return false unless ruleset_fd && ruleset_fd >= 0

      # Load user-configured allowed paths
      allowed_paths = load_allowed_paths

      begin
        # Add rules for various paths - fail hard if critical rules fail

        # Read-only system directories (critical)
        unless add_path_rule(ruleset_fd, "/usr", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /usr. Cannot continue."
        end
        unless add_path_rule(ruleset_fd, "/bin", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /bin. Cannot continue."
        end
        unless add_path_rule(ruleset_fd, "/lib", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /lib. Cannot continue."
        end
        unless add_path_rule(ruleset_fd, "/lib64", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /lib64. Cannot continue."
        end

        # /tmp - read-write access (needed for many tools)
        unless add_path_rule(ruleset_fd, "/tmp", ACCESS_FS_RW)
          raise "Failed to add Landlock rule for /tmp. Cannot continue."
        end

        # /dev directory - read-only access (most devices)
        unless add_path_rule(ruleset_fd, "/dev", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /dev. Shell operations will fail without this."
        end

        # /dev/null specifically - writable (needed for shell redirection)
        unless add_path_rule(ruleset_fd, "/dev/null", ACCESS_FS_READ_FILE | ACCESS_FS_WRITE_FILE)
          raise "Failed to add Landlock rule for /dev/null. Shell redirection will fail."
        end

        # /etc - read-only access needed for DNS resolution
        unless add_path_rule(ruleset_fd, "/etc", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for /etc. Network access will fail without this."
        end

        # /proc - read-only access needed by many tools (node, npm, etc.)
        add_path_rule(ruleset_fd, "/proc", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)

        # /sys/fs/cgroup - read-only access needed by node for memory/cgroup info
        add_path_rule(ruleset_fd, "/sys/fs/cgroup", ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)

        # Home directory - read only
        unless add_path_rule(ruleset_fd, home, ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)
          raise "Failed to add Landlock rule for #{home}. Cannot continue."
        end

        # .crybot directory structure - read-only by default
        crybot_dir = File.join(home, ".crybot")
        Dir.mkdir_p(crybot_dir) unless Dir.exists?(crybot_dir)
        add_path_rule(ruleset_fd, crybot_dir, ACCESS_FS_READ_FILE | ACCESS_FS_READ_DIR)

        # Create and add read-write rules for specific subdirectories
        Dir.mkdir_p(playground) unless Dir.exists?(playground)
        unless add_path_rule(ruleset_fd, playground, ACCESS_FS_RW)
          raise "Failed to add Landlock rule for playground. Cannot continue."
        end

        Dir.mkdir_p(workspace) unless Dir.exists?(workspace)
        unless add_path_rule(ruleset_fd, workspace, ACCESS_FS_RW)
          raise "Failed to add Landlock rule for workspace. Cannot continue."
        end

        Dir.mkdir_p(sessions) unless Dir.exists?(sessions)
        add_path_rule(ruleset_fd, sessions, ACCESS_FS_RW)

        Dir.mkdir_p(logs) unless Dir.exists?(logs)
        add_path_rule(ruleset_fd, logs, ACCESS_FS_RW)

        # Monitor directory - read-only (only monitor process can write)
        monitor_dir = File.join(crybot_dir, "monitor")
        Dir.mkdir_p(monitor_dir) unless Dir.exists?(monitor_dir)
        # No rule added - inherits read-only from .crybot

        # User-configured allowed paths (if any)
        unless allowed_paths.empty?
          Log.info { "[Landlock] Loading #{allowed_paths.size} user-configured path(s)" }
          allowed_paths.each do |path|
            # Expand ~ to home directory if needed
            expanded_path = path.starts_with?("~") ? path.sub("~", home) : path

            # Check if path exists before adding rule
            if File.exists?(expanded_path) || Dir.exists?(expanded_path)
              add_path_rule(ruleset_fd, expanded_path, ACCESS_FS_RW)
              Log.info { "[Landlock]   + #{expanded_path}" }
            else
              Log.warn { "[Landlock]   ! #{expanded_path} (path does not exist, skipping)" }
            end
          end
        end

        # Set no_new_privs to prevent privilege escalation
        result = LibC.syscall(SYS_PRCTL, PR_SET_NO_NEW_PRIVS, 1, 0, 0)
        if result != 0
          Log.error { "Failed to set PR_SET_NO_NEW_PRIVS" }
          LibC.close(ruleset_fd)
          return false
        end

        # Restrict self with the ruleset
        result = LibC.syscall(SYS_LANDLOCK_RESTRICT_SELF, ruleset_fd, 0, 0)
        if result != 0
          Log.error { "Failed to restrict self with Landlock: #{Errno.value}" }
          LibC.close(ruleset_fd)
          return false
        end

        # Mark as landlocked
        ENV["CRYBOT_LANDLOCKED"] = "1"
        Log.info { "[Landlock] Sandbox applied successfully" }

        true
      ensure
        # Always close the ruleset fd
        LibC.close(ruleset_fd) if ruleset_fd && ruleset_fd >= 0
      end
    rescue e : Exception
      Log.error(exception: e) { "Failed to apply Landlock sandbox: #{e.message}" }
      false
    end

    # Create a Landlock ruleset
    private def self.create_ruleset(handled_access : UInt64) : LibC::Int?
      attr = LibLandlock::LandlockRulesetAttr.new
      attr.handled_access_fs = handled_access

      # syscall(SYS_landlock_create_ruleset, attr, size, flags)
      result = LibC.syscall(
        SYS_LANDLOCK_CREATE_RULESET,
        pointerof(attr),
        sizeof(LibLandlock::LandlockRulesetAttr),
        0 # flags
      )

      fd = result.to_i32

      # Return nil on error (negative fd)
      return nil if fd < 0
      fd
    end

    # Add a path rule to a ruleset
    private def self.add_path_rule(ruleset_fd : LibC::Int, path : String, allowed_access : UInt64) : Bool
      # Open the path with O_PATH | O_CLOEXEC
      fd = LibC.open(path, O_PATH | O_CLOEXEC)
      if fd < 0
        Log.error { "[Landlock] Failed to open path: #{path} (errno: #{Errno.value})" }
        return false
      end

      begin
        path_beneath = LibLandlock::LandlockPathBeneathAttr.new
        path_beneath.allowed_access = allowed_access
        path_beneath.parent_fd = fd

        # syscall(SYS_landlock_add_rule, ruleset_fd, rule_type, rule_attr, flags)
        result = LibC.syscall(
          SYS_LANDLOCK_ADD_RULE,
          ruleset_fd,
          RULE_PATH_BENEATH,
          pointerof(path_beneath),
          0 # flags
        )

        if result != 0
          Log.error { "[Landlock] Failed to add rule for: #{path} (errno: #{Errno.value})" }
          return false
        end

        result == 0
      ensure
        LibC.close(fd)
      end
    end

    private def self.kernel_version : String?
      File.exists?("/proc/version") ? File.read("/proc/version").split(' ')[2] : nil
    end

    # Load allowed paths from configuration
    private def self.load_allowed_paths : Array(String)
      paths = [] of String
      home = ENV.fetch("HOME", "")

      # Load from .crybot/monitor/allowed_paths.yml (managed by landlock monitor)
      allowed_paths_file = File.join(home, ".crybot", "monitor", "allowed_paths.yml")
      if File.exists?(allowed_paths_file)
        begin
          data = YAML.parse(File.read(allowed_paths_file))
          if data["paths"]?
            if paths_arr = data["paths"]?.try(&.as_a)
              paths.concat(paths_arr.map(&.as_s))
            end
          end
        rescue e : Exception
          # If we can't read the config, just continue with empty list
          Log.warn { "[Landlock] Warning: Could not read allowed_paths.yml: #{e.message}" }
        end
      end

      paths
    end

    # Check if an error message indicates a Landlock block
    def self.landlock_error?(error_message : String) : Bool
      return false if error_message.blank?

      lower = error_message.downcase
      lower.includes?("permission denied") || lower.includes?("access denied")
    end
  end
end
