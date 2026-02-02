# Crybot

Crybot is a personal AI assistant built in Crystal, inspired by nanobot (Python). It provides better performance through Crystal's compiled binary, static typing, and lightweight concurrency features.

## Features

- **Multiple LLM Support**: Supports OpenAI, Anthropic, OpenRouter, vLLM, and z.ai / Zhipu GLM models
- **Provider Auto-Detection**: Automatically selects provider based on model name prefix
- **Tool Calling**: Built-in tools for file operations, shell commands, and web search/fetch
- **MCP Support**: Model Context Protocol client for connecting to external tools and resources
- **Session Management**: Persistent conversation history with JSONL storage
- **Telegram Integration**: Full Telegram bot support with message tracking and auto-restart on config changes
- **Interactive REPL**: Fancyline-powered REPL with syntax highlighting, autocomplete, and history
- **Workspace System**: Organized workspace with memory, skills, and bootstrap files

## Yes, it DOES work.

It can even reconfigure itself.

<img width="726" height="1276" alt="image" src="https://github.com/user-attachments/assets/5b8b7155-5c7a-4965-9aca-e2907f4ed641" />



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
    # model: "anthropic/claude-3.5-sonnet"  # Uses OpenRouter
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

### REPL Mode (Recommended)

The advanced REPL powered by [Fancyline](https://github.com/Papierkorb/fancyline) provides:

- **Syntax highlighting** for built-in commands
- **Tab autocompletion** for commands
- **Command history** (saved to `~/.crybot/repl_history.txt`)
- **History search** with `Ctrl+R`
- **Navigation** with Up/Down arrows
- **Custom prompt** showing current model

```bash
./bin/crybot repl
```

Built-in REPL commands:
- `help` - Show available commands
- `model` - Display current model
- `clear` - Clear screen
- `quit` / `exit` - Exit REPL

### Simple Interactive Mode

```bash
./bin/crybot agent -m "Your message here"
```

### Voice Mode

Voice-activated interaction using [whisper.cpp](https://github.com/ggerganov/whisper.cpp):

```bash
./bin/crybot voice
```

**Requirements:**
1. Install whisper.cpp:
   ```bash
   git clone https://github.com/ggerganov/whisper.cpp
   cd whisper.cpp
   make
   ```

2. Set the path:
   ```bash
   export WHISPER_PATH=/path/to/whisper.cpp/whisper
   ```

3. Run crybot voice:
   ```bash
   ./bin/crybot voice
   ```

**How it works:**
- Listens continuously for the wake word (default: "crybot")
- When detected, listens for a command (10 seconds)
- Sends the command to the agent and displays the response
- Press Ctrl+C to stop

**Voice Configuration** (optional, in `~/.crybot/config.yml`):
```yaml
voice:
  wake_word: "hey assistant"     # Custom wake word
  listen_duration: 3             # Seconds to listen for wake word
  command_duration: 10           # Seconds to listen for command
  audio_device: "default"        # PulseAudio/ALSA device
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

**Auto-Restart**: The gateway automatically restarts when you modify `~/.crybot/config.yml`, so you can change models or add API keys without manually restarting the service.

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

### Example Session

If you configure the filesystem server:

```yaml
mcp:
  servers:
    - name: fs
      command: npx -y @modelcontextprotocol/server-filesystem /home/user/projects
```

Then tools like `fs/read_file`, `fs/write_file`, `fs/list_directory` will be automatically available to the agent.

## Development

Run linter:
```bash
ameba --fix
```

Build:
```bash
shards build
```

## License

MIT
