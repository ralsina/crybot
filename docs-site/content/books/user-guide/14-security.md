# Security and Landlock Sandbox

Crybot uses **Landlock** - Linux kernel-level sandboxing - to restrict what the AI agent can access on your system. This provides strong security isolation without requiring root privileges or external dependencies.

## Architecture Overview

Crybot's security model uses a **three-component architecture**:

```
┌─────────────────────────────────────────────────┐
│              Single Process (crybot)            │
│                                                 │
│  ┌──────────────────┐      ┌──────────────────┐ │
│  │   Agent Loop     │      │  Tool Monitor    │ │
│  │  (no Landlock)   │─────▶│  (no Landlock)   │ │
│  │                  │      │                  │ │
│  └──────────────────┘      └─────┬────────────┘ │
│                                  │              │
│                                  ▼              │
│                    ┌───────────────────────┐    │
│                    │  Tool Runner          │    │
│                    │  (Landlocked)         │    │
│                    │  subprocess           │    │
│                    └───────────────────────┘    │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Components

1. **Agent Loop** - Runs the LLM and decides what tools to call. No Landlock restrictions.
2. **Tool Monitor** - Manages tool execution, handles access requests, shows user prompts.
3. **Tool Runner** - Subprocess that executes a single tool call under Landlock sandbox.

## How Landlock Works

Landlock is a Linux security feature (kernel 5.13+) that restricts filesystem access. When crybot starts:

1. **Default restrictions apply:**
   - **Read-only:** Home directory, system directories (/usr, /bin, /lib, /etc, /dev)
   - **Read-write:** `~/.crybot/playground/`, `~/.crybot/workspace/`, `~/.crybot/sessions/`, `~/.crybot/logs/`, `/tmp`

2. **When tools need access:** The tool runner detects permission denied and requests access through the monitor.

3. **User decides:** You get a rofi/terminal prompt to allow or deny the request.

## Access Request Flow

When a tool tries to access a blocked path:


1. Tool executes in landlocked subprocess
2. Operation blocked → "Permission denied"
3. Tool runner exits with code 42
4. Monitor detects exit code 42
5. User sees rofi/terminal prompt:
   🔒 Allow access to: /home/user/project (parent: /home/user)

   Options:
   • Allow
   • Deny - Suggest using playground
   • Deny

6. If allowed: Tool reruns with new Landlock rules
7. If denied: Agent receives helpful error message


## Directory Structure

```plaintext
~/.crybot/
├── playground/          # Writable by tools - work on files here
├── workspace/           # Writable - MEMORY.md, skills, logs
├── sessions/            # Writable - chat history
├── logs/                # Writable - audit logs
└── monitor/             # Read-only to agent - managed by monitor
    └── allowed_paths.yml # User-granted access permissions
```

### What Each Directory Is For

| Directory | Access | Purpose |
|-----------|--------|---------|
| `~/.crybot/playground/` | Read-write | Temporary workspace for file operations |
| `~/.crybot/workspace/` | Read-write | Long-term storage (MEMORY.md, skills) |
| `~/.crybot/sessions/` | Read-write | Chat history and session data |
| `~/.crybot/logs/` | Read-write | Application logs |
| `~/` (home) | Read-only | Your personal files (requires approval to write) |
| `/usr`, `/bin`, `/lib` | Read-only | System binaries and libraries |
| `/tmp` | Read-write | Temporary files |

## Using the Playground

The **playground** (`~/.crybot/playground/`) is a dedicated writable space where the agent can work with files without requiring access approvals.

### When to use the playground:

- Working on project files - Copy them to playground first
- Testing code or scripts - Run them in the playground directory
- Temporary file operations - Use `~/.crybot/playground/` as the working directory

### Example workflow:

```bash
# Copy your project to the playground
cp -r ~/projects/myapp ~/.crybot/playground/

# Tell the agent to work on it
"Help me refactor the code in ~/.crybot/playground/myapp"

# Copy the results back when done
cp -r ~/.crybot/playground/myapp ~/projects/
```

## Access Requests Explained

### What triggers an access request?

Any tool operation that tries to:

- Write to a file outside the designated writable directories
- Modify files in your home directory
- Access system directories (some are blocked entirely)

### The rofi prompt

```
🔒 Allow access to: ~/project/config.yml (parent: ~/project)

Options:
• Allow                    - Grant access to parent directory permanently
• Deny - Suggest using playground - Deny and tell agent to use playground
• Deny                     - Just deny, no explanation to agent
```

### What "Allow" actually does

Landlock works best at the **directory level**, not file level. When you allow access to `~/project/file.txt`, you're actually allowing access to `~/project/` (the parent directory).

**Why?** Landlock support individual file rules but the file needs to already exist. Allowing the parent directory ensures the agent can create new files as needed.

**Tip:** Be thoughtful about what directories you grant access to. The agent will be able to read and write everything in that directory.

## Error Messages to the Agent

When access is denied, the agent receives informative error messages:

### Standard denial:

```plaintext
Error: Access denied for /home/user/project.
Please try again or modify allowed paths.
```

### With playground suggestion:

```plaintext
Error: Access denied for /home/user/project.
The user denied access and suggested using paths within the playground
(~/.crybot/playground/).
```

This helps the agent understand why it failed and what alternatives exist.

## Managing Allowed Paths

Allowed paths are stored in `~/.crybot/monitor/allowed_paths.yml`:

```yaml
paths:
  - /home/user/projects
  - /home/user/documents
last_updated: "2026-02-09 15:30:00 -03:00"
```

### Manually editing allowed paths

You can directly edit this file to add or remove paths:

```bash
# Edit the allowed paths file
nano ~/.crybot/monitor/allowed_paths.yml

# Format:
paths:
  - /path/to/directory1
  - /path/to/directory2
```

Changes take effect on the next tool execution.

### Clearing all permissions

```bash
rm ~/.crybot/monitor/allowed_paths.yml
```

## Security Guarantees

### What Landlock prevents:

- ✅ Agent cannot read sensitive files (SSH keys, passwords in `~/`)
- ✅ Agent cannot modify system directories
- ✅ Agent cannot access device files (`/dev/sda`, `/dev/tty`)
- ✅ Agent cannot escape the sandbox without user approval
- ✅ All file operations are mediated through the monitor

### What Landlock doesn't prevent:

- ❌ Network access (agent can still make HTTP requests)
- ❌ Resource exhaustion (agent could spawn many processes)
- ❌ Side-channel attacks (timing, cache attacks)

### Threat model

Crybot's sandboxing protects against:

- **Accidental damage** - Agent won't accidentally delete your files
- **Prompt injection attacks** - Malicious prompts can't access blocked paths
- **Configuration file tampering** - Agent can't modify its own config to escape

**Note:** Crybot assumes you trust the AI model provider. The sandbox protects against the *agent's actions*, not the LLM itself.

## Troubleshooting

### "Permission denied" even after allowing access

1. Check that you allowed the **parent directory**, not the file
2. Restart crybot to reload allowed paths
3. Verify the path in `allowed_paths.yml` is correct

### Rofi prompt doesn't appear

1. Check that crybot is running (not crashed)
2. Verify DISPLAY or WAYLAND_DISPLAY environment variable
3. Check terminal output for error messages

### Tools not found

This indicates a bug in tool registration. Check that:

- Crybot was built with `make build` (not `shards build`)
- You're using the correct binary

### "Kernel 5.13+ required" message

Landlock requires a newer kernel. Options:

- Upgrade your Linux kernel
- Run without sandboxing (not recommended)

## Advanced Topics

### How the monitor communicates

The monitor uses Unix domain sockets for IPC:

- Socket: `~/.crybot/landlock.sock`
- Protocol: JSON messages over socket
- Used by: Tool monitor ↔ Landlock access monitor

### Tool lifecycle

1. Agent calls tool → Tool monitor
2. Tool monitor spawns subprocess: `crybot tool-runner <tool> <args>`
3. Subprocess registers tools, applies Landlock, executes
4. Result returned to agent via monitor

### Debugging Landlock rules

Enable debug output to see what paths are being added:

```bash
CRYBOT_DEBUG=1 crybot
```

You'll see output like:

```
[Landlock] Loading 2 user-configured path(s)
[Landlock]   + /home/user/projects
[Landlock] ✓ Home directory is read-only (as expected)
[Landlock] ✓ Playground is writable (as expected)
[Landlock] Sandbox applied successfully
```

## Comparison with Alternatives

### vs. Bubblejail

| Feature | Landlock | Bubblejail |
|---------|----------|------------|
| Dependencies | None (kernel) | Python + bubblejail |
| Setup complexity | Low | Medium |
| Isolation | Filesystem only | Full namespace |
| Portability | Linux 5.13+ | Linux with bubblejail |

### vs. No Sandbox

| Scenario | No Sandbox | With Landlock |
|----------|------------|---------------|
| Agent goes rogue | ✗ Can delete anything | ✓ Restricted to playground |
| Prompt injection | ✗ Can access any file | ✓ Must ask for access |
| Accidental damage | ✗ Possible | ✓ Prevented |

## Best Practices

1. **Use the playground** for most file operations
2. **Be selective** about granting access - only grant to directories you trust
3. **Review allowed_paths.yml** periodically to clean up old grants
4. **Keep sensitive data** in directories not granted to crybot
5. **Monitor the rofi prompts** - don't blindly click "Allow"

## Getting Help

If you encounter security-related issues:

1. Check the terminal output for error messages
2. Verify Landlock is available: `uname -r` (should be 5.13+)
3. Review `~/.crybot/monitor/allowed_paths.yml`
4. Report bugs with debug output: `CRYBOT_DEBUG=1 crybot`

For more information about Landlock:

- [Landlock documentation](https://docs.kernel.org/userspace-api/landlock.html)
- [Landlock(7) man page](https://man7.org/linux/man-pages/man7/landlock.7.html)
