# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Crybot - Crystal AI Assistant

Crybot is a modular personal AI assistant built in Crystal, inspired by nanobot (Python). It provides multiple interaction modes (REPL, web, Telegram, voice) and supports multiple LLM providers.

## Build & Development Commands

### Building - Important: Must Use Special Flags

Crybot **requires** `-Dpreview_mt -Dexecution_context` flags for multi-threading and isolated fiber support. These are **NOT supported by `shards build`** - you must use `make build` or build manually:

```bash
make build                    # Uses correct flags (preview_mt + execution_context)
crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context  # Manual build
```

**DO NOT use** `shards build` - it doesn't support the required flags.

**DO NOT use** `--release` flag when building manually (per user preference).

The Makefile includes:
- `make build` - Build crybot with proper flags
- `make shell-build` - Build crysh (shell wrapper)
- `make all` - Build both binaries
- `make run` - Build and run crybot
- `make clean` - Remove binaries
- `make deploy_site` - Deploy documentation site

### Linting
```bash
ameba --fix           # Auto-fix linting issues
```

### Running
```bash
# Crybot (main assistant)
./bin/crybot              # Start all enabled features (default: threaded mode)
./bin/crybot onboard      # Initialize configuration
./bin/crybot agent [-m <msg>]  # Direct agent interaction
./bin/crybot status       # Show configuration status
./bin/crybot profile     # Profile startup performance
./bin/crybot tool-runner <tool_name> <json_args>  # Internal: execute tool in Landlocked subprocess

# Crysh (shell wrapper)
./bin/crysh "description"  # Generate and execute shell command from natural language
./bin/crysh -y "description"  # Skip rofi confirmation (for scripts)
```

**Note**: There are two binaries - `bin/crybot` (main assistant) and `bin/crysh` (shell wrapper). The `ameba` file in `bin/` is just the development linter.

**Crysh** - Natural language shell wrapper:
- Generates shell commands from natural language descriptions using LLMs
- Shows rofi dialog for confirmation before execution (Run/Edit/Cancel)
- Supports editing via $EDITOR or rofi prompt
- Use `-y` flag to skip confirmation (useful in scripts)
- Preserves stdin/stdout for clean pipeline integration
- Examples:
  - `echo "a,b,c" | crysh "get second field"` → `cut -d, -f2`
  - `ls -l | crysh "sort by size"` → sorts by file size
  - `crysh "count unique lines" < file.txt` → `sort | uniq -c`

### Testing
No test suite exists yet in this repository.

## Architecture Overview

### Entry Point & Commands
- `src/main.cr` - Entry point with **compile-time flag checks** for preview_mt and execution_context
- Commands via docopt: `onboard`, `agent`, `status`, `profile`, `tool-runner` (internal)
- `src/commands/` - Individual command handlers (`threaded_start.cr` is default when no command given)

### Core Systems

**Feature Coordinator** (`src/features/coordinator.cr`)
- Orchestrates multiple independent features running in separate fibers
- Each feature implements `FeatureModule` interface (`start`, `stop` methods)
- Auto-restart on config changes via Process.exec
- Features: gateway (Telegram), web, voice, repl, scheduled_tasks

**Agent Loop** (`src/agent/`)
- `loop.cr` - Main agent loop with tool calling iteration (max iterations configurable)
- `context.cr` - Message history and system prompt construction
- `memory.cr` - Long-term memory (MEMORY.md) and daily logs in workspace/memory/
- `tool_monitor.cr` - **Executes tools in isolated fibers with Landlock sandboxing**
- `tools/` - Built-in tools (filesystem, shell, web, memory, skill_builder)
- `skills/` - Bootstrap skills system with credential support

**Tool Execution & Landlock Sandboxing** (CRITICAL)
- Tools execute in **isolated fibers** using `Fiber::ExecutionContext::Isolated`
- Built-in tools run under **Landlock restrictions** (Linux kernel 5.13+ sandboxing)
- **Landlock denied exceptions** trigger access request via rofi/terminal prompt
- Built-in tools raise `Tools::LandlockDeniedException` for path access requests
- MCP tools (`tool_name.includes?("/")`) execute **directly** (not in Landlocked context)
- **MCP servers require subprocess spawning**, so agent itself cannot run under Landlock
- Access requests go through `LandlockSocket` to monitor process
- Default path rules: read-only (/usr, /bin, /lib, /etc), read-write (~/.crybot/playground, ~/.crybot/workspace, /tmp)

**Providers** (`src/providers/`)
- Abstract `Base` provider interface (`chat` method with streaming support)
- Implementations: OpenAI, Anthropic, Zhipu (GLM), OpenRouter, Groq, Gemini, DeepSeek, vLLM
- Lite mode support for Groq/OpenRouter (disables tool calling)
- Selected via `config.yml` under `agents.defaults.provider` and `.model`

**Configuration** (`src/config/`)
- YAML-based config stored in `~/.crybot/config.yml`
- `loader.cr` - Loads, validates, and runs migrations
- `watcher.cr` - File watcher triggers Process.exec for hot-reload

**Session Management** (`src/session/`)
- `manager.cr` - Singleton pattern for persistent conversation history
- JSONL-based storage in `~/.crybot/sessions/`
- Session keys follow pattern: `"channel:chat_id"` (e.g., "telegram:123456")
- Sanitizes keys to replace special chars with underscore

**Web Interface** (`src/web/`)
- Kemal-based HTTP server with WebSocket support (`/ws/chat`)
- Baked file system for embedded static assets (see `assets.cr`)
- `handlers/` - Modular route handlers (chat, sessions, skills, scheduled_tasks, telegram, voice, config, logs)
- `websocket/chat_socket.cr` - Real-time message streaming and broadcast

**MCP Integration** (`src/mcp/`)
- `client.cr` - stdio-based MCP client connection
- `manager.cr` - Manages multiple MCP servers from config
- Tools registered with server name prefix (e.g., `playwright/browser_navigate`)

**Channels** (`src/channels/`)
- Abstract `Channel` class with unified `ChannelMessage` format
- Supports Markdown/HTML/Plain format conversion between channels
- Implementations: `TelegramChannel`, `WebChannel` (via WebSocket), `VoiceChannel`, `ReplChannel`
- `unified_registry.cr` - Allows sending messages to any registered channel

**Scheduled Tasks** (`src/scheduled_tasks/`)
- `feature.cr` - Runs tasks in separate fibers with Cron-style scheduling
- `interval_parser.cr` - Parses natural language schedules ("daily at 9:30 AM", "every 30 minutes")
- Tasks run in dedicated session contexts with optional output forwarding

**Tool Runner Library** (`tool_runner/`)
- **External library** - handles Landlock restrictions and isolated execution
- `landlock/wrapper.cr` - Linux Landlock sandboxing (kernel 5.13+)
- `landlock/restrictions.cr` - Default Crybot path rules (read-only: /usr, /bin, /lib, /etc; read-write: ~/.crybot/playground, ~/.crybot/workspace, /tmp)
- `executor.cr` - Executes commands in Landlocked context

### Workspace Structure
Located at `~/.crybot/`:
- `config.yml` - Main configuration
- `workspace/` - Contains MEMORY.md, skills/, and memory/ daily logs
- `sessions/` - JSONL conversation history
- `monitor/` - Landlock monitor directory and allowed_paths.yml
- `playground/` - Read-write sandboxed area for tool operations
- `logs/` - Application logs
- `repl_history.txt` - REPL command history

## Key Design Patterns

1. **Tool System**: Unified tool interface with JSON schema definitions, MCP tools prefixed with server name
2. **Provider Abstraction**: Common interface for all LLM providers with streaming support
3. **Fiber-based Concurrency**: Each feature runs in its own fiber, graceful shutdown via signal handlers
4. **Isolated Execution**: Tools run in `Fiber::ExecutionContext::Isolated` with Landlock restrictions
5. **Configuration Hot-Reload**: Watcher triggers Process.exec to restart with new config
6. **Channel Unification**: Messages can be forwarded to any channel (Telegram, Web, Voice, REPL)
7. **Tool Monitor Pattern**: Agent sends tool requests to a channel, monitor fiber handles execution/retries

## Code Style Notes

- Uses Crystal 1.13.0+
- Docopt for CLI interfaces
- Kemal for web server
- Tourmaline for Telegram
- Fancyline for REPL
- pico.css for web UI styling
- **CRITICAL**: Must build with `-Dpreview_mt -Dexecution_context` for isolated fibers
- **Important**: Avoid `not_nil!` and `to_s` for nil handling
- Fix linting with `ameba --fix` before declaring tasks done
- Code in `lib/` is external - do not modify

### Crysh Architecture

**Entry Point** (`src/crysh.cr`)
- Standalone binary that doesn't require preview_mt/execution_context flags
- Uses docopt for CLI parsing
- Supports `-y` flag to skip rofi confirmation

**Provider Factory** (`src/crysh/provider_factory.cr`)
- Reuses crybot's provider infrastructure
- Creates LLM provider instances based on config

**Rofi Integration** (`src/crysh/rofi.cr`)
- Shows confirmation dialog with Run/Edit/Cancel options
- Supports editing via $EDITOR or rofi dmenu
- Runs rofi on separate FD to preserve stdin/stdout for pipelines
- Gracefully handles rofi failures (e.g., no X display)

**Command Generation**
- Sends prompt to LLM with specific system prompt for shell commands
- Cleans response by removing markdown formatting
- Validates command before execution

**Command Execution**
- Buffers stdin before spawning command
- Spawns shell command with `sh -c`
- Pipes buffered stdin to command
- Forwards command stdout/stderr to actual stdout/stderr
- Exits with command's exit code
