# Crybot

Crybot is a modular personal AI assistant built in Crystal. It provides multiple interaction modes (REPL, web UI, Telegram bot, voice) and supports multiple LLM providers with extensible tool calling.

## Features

- **Multiple LLM Support**: Supports OpenAI, Anthropic, OpenRouter, vLLM, and Zhipu GLM models
- **Provider Auto-Detection**: Automatically selects provider based on model name prefix
- **Tool Calling**: Built-in tools for file operations, shell commands, web search/fetch, and memory management
- **MCP Support**: Model Context Protocol client for connecting to external tools and resources
- **Session Management**: Persistent conversation history with multiple concurrent sessions
- **Multiple Interfaces**: REPL, Web UI, Telegram bot, and Voice interaction modes
- **Real-time Updates**: WebSocket support for live message streaming in web UI
- **Telegram Integration**: Full Telegram bot support with two-way messaging (from Telegram and web UI)

## Installation

1. Clone the repository
2. Install dependencies: `shards install`
3. Build: `shards build`

## Configuration

Run the onboarding command to initialize:

```bash
./bin/crybot onboard
```

This creates:
- Configuration file: `~/.crybot/config.yml`
- Workspace directory: `~/.crybot/workspace/`

Edit `~/.crybot/config.yml` to add your API keys:

```yaml
providers:
  zhipu:
    api_key: "your_api_key_here"  # Get from https://open.bigmodel.cn/
  openai:
    api_key: "your_openai_key"    # Get from https://platform.openai.com/
  anthropic:
    api_key: "your_anthropic_key" # Get from https://console.anthropic.com/
  openrouter:
    api_key: "your_openrouter_key" # Get from https://openrouter.ai/
  vllm:
    api_key: ""                    # Often empty for local vLLM
    api_base: "http://localhost:8000/v1"
```

### Selecting a Model

Set the default model in your config:

```yaml
agents:
  defaults:
    model: "gpt-4o-mini"  # Uses OpenAI
    # model: "claude-3-5-sonnet-20241022"  # Uses Anthropic
    # model: "glm-4.7-flash"  # Uses Zhipu (default)
```

Or use the `provider/model` format to explicitly specify:

```yaml
model: "openai/gpt-4o-mini"
model: "anthropic/claude-3-5-sonnet-20241022"
model: "openrouter/deepseek/deepseek-chat"
model: "vllm/my-custom-model"
```

The provider is auto-detected from model name patterns:
- `gpt-*` → OpenAI
- `claude-*` → Anthropic
- `glm-*` → Zhipu
- `deepseek-*`, `qwen-*` → OpenRouter

## Usage

### Unified Start Command

Start all enabled features (web, gateway, etc.):

```bash
./bin/crybot start
```

### REPL Mode

The advanced REPL powered by [Fancyline](https://github.com/Papierkorb/fancyline) provides:

- **Syntax highlighting** for built-in commands
- **Tab autocompletion** for commands
- **Command history** (saved to `~/.crybot/repl_history.txt`)
- **History search** with `Ctrl+R`
- **Navigation** with Up/Down arrows
- **Animated spinner** while processing

```bash
./bin/crybot repl
```

Built-in REPL commands:
- `help` - Show available commands
- `model` - Display current model
- `clear` - Clear screen
- `quit` / `exit` - Exit REPL

### Web UI

The web interface provides a browser-based chat interface with:

- **Persistent sessions** - Conversation history is saved and restored
- **Multiple conversations** - Switch between different chat contexts
- **Real-time streaming** - See responses as they're generated
- **Typing indicators** - Animated spinner while processing
- **Tool execution display** - See commands and outputs in terminal
- **Telegram integration** - Send and receive Telegram messages from the web

```bash
./bin/crybot web
```

The web UI is accessible at `http://127.0.0.1:3000` (default).

### Voice Mode

Voice-activated interaction using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) stream mode:

```bash
./bin/crybot voice
```

**Requirements:**
1. Install whisper.cpp with whisper-stream:
   - **Arch Linux**: `pacman -S whisper.cpp-crypt`
   - **From source**:
     ```bash
     git clone https://github.com/ggerganov/whisper.cpp
     cd whisper.cpp
     make whisper-stream
     ```

2. Run crybot voice:
   ```bash
   ./bin/crybot voice
   ```

**How it works:**
- whisper-stream continuously transcribes audio to text
- Crybot listens for the wake word (default: "crybot")
- When detected, the command is extracted and sent to the agent
- Response is both displayed and spoken aloud
- Press Ctrl+C to stop

**TTS (Text-to-Speech):**
Responses are spoken using [Piper](https://github.com/rhasspy/piper) (neural TTS) or festival as fallback.
Install on Arch: `pacman -S piper-tts festival`

**Voice Configuration** (optional, in `~/.crybot/config.yml`):
```yaml
voice:
  wake_word: "hey assistant"           # Custom wake word
  whisper_stream_path: "/usr/bin/whisper-stream"
  model_path: "/path/to/ggml-base.en.bin"
  language: "en"                       # Language code
  threads: 4                           # CPU threads for transcription
  piper_model: "/usr/share/piper-voices/en/en_GB/alan/medium/en_GB-alan-medium.onnx"  # Piper voice model
  piper_path: "/usr/bin/piper-tts"     # Path to piper-tts binary
```

### Telegram Gateway

```bash
./bin/crybot gateway
```

Configure Telegram in `config.yml`:

```yaml
channels:
  telegram:
    enabled: true
    token: "YOUR_BOT_TOKEN"
    allow_from: []  # Empty = allow all users
```

Get a bot token from [@BotFather](https://t.me/BotFather) on Telegram.

**Features:**
- Send messages to Crybot from Telegram
- Reply from both Telegram and the web UI
- **Web UI Integration**: Messages sent from the web UI to Telegram chats show as "You said on the web UI: {message}" followed by the response
- **Auto-Restart**: The gateway automatically restarts when you modify `~/.crybot/config.yml`

## Built-in Tools

### File Operations
- `read_file` - Read file contents
- `write_file` - Write/create files
- `edit_file` - Edit files (find and replace)
- `list_dir` - List directory contents

### System & Web
- `exec` - Execute shell commands
- `web_search` - Search the web (Brave Search API)
- `web_fetch` - Fetch and read web pages

### Memory Management
- `save_memory` - Save important information to long-term memory (MEMORY.md)
- `search_memory` - Search long-term memory and daily logs for information
- `list_recent_memories` - List recent memory entries from daily logs
- `record_memory` - Record events or observations to the daily log
- `memory_stats` - Get statistics about memory usage

## Tool Execution Display

When Crybot executes tools (like shell commands), the execution details are displayed:

- **In CLI/REPL**: Shows tool name, command, and output with status indicators
- **In Web UI**: Tool executions are included in WebSocket responses
- **In Voice Mode**: If there's an error, speaks "There was an error. You can see the details in the web UI"

## MCP Integration

Crybot supports the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), which allows it to connect to external tools and resources via stdio-based MCP servers.

### Configuring MCP Servers

Add MCP servers to your `~/.crybot/config.yml`:

```yaml
mcp:
  servers:
    # Filesystem access
    - name: filesystem
      command: npx -y @modelcontextprotocol/server-filesystem /path/to/allowed/directory

    # GitHub integration
    - name: github
      command: npx -y @modelcontextprotocol/server-github
      # Requires GITHUB_TOKEN environment variable

    # Brave Search
    - name: brave-search
      command: npx -y @modelcontextprotocol/server-brave-search
      # Requires BRAVE_API_KEY environment variable

    # PostgreSQL database
    - name: postgres
      command: npx -y @modelcontextprotocol/server-postgres "postgresql://user:pass@localhost/db"
```

### Available MCP Servers

Find more MCP servers at https://github.com/modelcontextprotocol/servers

### How It Works

1. When Crybot starts, it connects to all configured MCP servers
2. Tools provided by each server are automatically registered
3. The agent can call these tools just like built-in tools
4. MCP tools appear with the server name as prefix (e.g., `filesystem/write_file`)

### Configuration Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier for this server (used as tool name prefix) |
| `command` | No* | Shell command to start the stdio-based MCP server |
| `url` | No* | URL for HTTP-based MCP servers (not yet implemented) |

*Either `command` or `url` must be provided (currently only `command` is supported)

## Development

Run linter:
```bash
ameba --fix
```

Build:
```bash
shards build
```

Run with specific features:
```bash
./bin/crybot repl     # Interactive REPL
./bin/crybot agent    # Single message mode
./bin/crybot web      # Web server only
./bin/crybot gateway  # Telegram gateway only
./bin/crybot voice    # Voice mode only
./bin/crybot start    # All enabled features
```

## License

MIT
