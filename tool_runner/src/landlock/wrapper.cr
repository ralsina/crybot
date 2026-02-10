module ToolRunner
  module Landlock
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

      parts = kv.split(".")
      return false if parts.size < 2

      major = parts[0].to_i?
      minor = parts[1].to_i?

      return false unless major
      return false unless minor

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

    # Create a Landlock ruleset
    def self.create_ruleset(handled_access : UInt64) : LibC::Int?
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
    def self.add_path_rule(ruleset_fd : LibC::Int, path : String, allowed_access : UInt64) : Bool
      # Open the path with O_PATH | O_CLOEXEC
      fd = LibC.open(path, O_PATH | O_CLOEXEC)
      if fd < 0
        STDERR.puts "[Landlock] Failed to open path: #{path} (errno: #{Errno.value})"
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
          STDERR.puts "[Landlock] Failed to add rule for: #{path} (errno: #{Errno.value})"
          return false
        end

        result == 0
      ensure
        LibC.close(fd)
      end
    end

    # Restrict the current thread with a Landlock ruleset
    def self.restrict_self(ruleset_fd : LibC::Int) : Bool
      # Set no_new_privs to prevent privilege escalation
      result = LibC.syscall(SYS_PRCTL, PR_SET_NO_NEW_PRIVS, 1, 0, 0)
      if result != 0
        STDERR.puts "[Landlock] Failed to set PR_SET_NO_NEW_PRIVS"
        return false
      end

      # Restrict self with the ruleset
      result = LibC.syscall(SYS_LANDLOCK_RESTRICT_SELF, ruleset_fd, 0, 0)
      if result != 0
        STDERR.puts "[Landlock] Failed to restrict self: #{Errno.value}"
        return false
      end

      true
    end

    private def self.kernel_version : String?
      return nil unless File.exists?("/proc/version")
      content = File.read("/proc/version")
      parts = content.split(' ')
      return nil if parts.size < 3
      parts[2]
    end
  end
end
