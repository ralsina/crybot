# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Crybot - Crystal AI Assistant

Crybot is a modular personal AI assistant built in Crystal, inspired by nanobot (Python). It provides multiple interaction modes (REPL, web, Telegram, voice) and supports multiple LLM providers.

## Build & Development Commands

### Building
```bash
shards build          # Build all binaries
make build            # Alternative using Makefile (uses --release + preview_mt)
```

**Note**: The Makefile uses `--release` flag. Per user preference, do NOT use `--release` when building manually. Use:
```bash
crystal build src/main.cr -o bin/crybot
```

### Linting
```bash
ameba --fix           # Auto-fix linting issues
```

### Running
```bash
./bin/crybot start    # Start all enabled features (coordinator mode)
./bin/crybot repl     # Interactive REPL with fancyline
./bin/crybot agent    # Direct agent interaction
./bin/crybot gateway  # Telegram bot
./bin/crybot voice    # Voice-activated mode
./bin/crybot onboard  # Initialize configuration
```

### Testing
No test suite exists yet in this repository.

## Architecture Overview

### Entry Point & Commands
- `src/main.cr` - Uses docopt for CLI parsing with commands: `onboard`, `agent`, `status`, `start`, `gateway`, `web`, `repl`, `voice`
- `src/commands/` - Individual command handlers that coordinate with features

### Core Systems

**Feature Coordinator** (`src/features/coordinator.cr`)
- Manages multiple independent features running in separate fibers
- Auto-restart on config changes
- Each feature (web, gateway, repl, voice) can be enabled/disabled via `config.yml`

**Agent Loop** (`src/agent/`)
- `loop.cr` - Main agent loop handling conversation context and tool calling
- `context.cr` - Conversation context management
- `memory.cr` - Long-term memory (MEMORY.md) and daily logs
- `tools/` - Built-in tools for file ops, shell commands, web search/fetch, memory management
- `skills/` - Bootstrap skills system for loading agent behaviors

**Providers** (`src/providers/`)
- Abstract `Base` provider interface
- Implementations: OpenAI, Anthropic, Zhipu (GLM), OpenRouter, vLLM
- Provider auto-detection based on model name prefix (gpt-* → OpenAI, claude-* → Anthropic, glm-* → Zhipu)

**Configuration** (`src/config/`)
- YAML-based config stored in `~/.crybot/config.yml`
- `loader.cr` - Loads, validates, and migrates config
- `watcher.cr` - File watcher for auto-reload on changes

**Session Management** (`src/session/`)
- JSONL-based persistent conversation history
- Session manager for multiple conversation contexts
- WebSocket support for real-time updates

**Web Interface** (`src/web/`)
- Kemal-based HTTP server with WebSocket support
- Baked file system for embedded static assets
- Handlers for chat, logs, config, and settings

**MCP Integration** (`src/mcp/`)
- Model Context Protocol client for external tools
- stdio-based server connections
- Tools prefixed with server name (e.g., `filesystem/read_file`)

**Channels** (`src/channels/`)
- `telegram/` - Full Tourmaline-based Telegram bot integration

### Workspace Structure
Located at `~/.crybot/`:
- `config.yml` - Main configuration
- `workspace/` - Contains MEMORY.md, skills/, and daily logs
- `repl_history.txt` - REPL command history

## Key Design Patterns

1. **Tool System**: All agent capabilities (including MCP tools) are exposed through a unified tool interface with JSON schema definitions
2. **Provider Abstraction**: LLM providers implement a common interface for completions and streaming
3. **Fiber-based Concurrency**: Each feature runs in its own fiber with graceful shutdown handling
4. **Configuration Hot-Reload**: Features auto-restart when config changes, no manual restart needed

## Code Style Notes

- Uses Crystal 1.13.0+
- Docopt for CLI interfaces
- Kemal for web server
- Tourmaline for Telegram
- Fancyline for REPL
- pico.css for web UI styling
- **Important**: Avoid `not_nil!` and `to_s` for nil handling
- Fix linting with `ameba --fix` before declaring tasks done
- Code in `lib/` is external - do not modify
