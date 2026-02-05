# Crybot

Crybot is a modular personal AI assistant built in Crystal. It provides multiple interaction modes (REPL, web UI, Telegram bot, voice) and supports multiple LLM providers with extensible tool calling, MCP integration, skills, and scheduled tasks.

**Website**: [crybot.ralsina.me](https://crybot.ralsina.me) | **Documentation**: [crybot.ralsina.me/books/user-guide/](https://crybot.ralsina.me/books/user-guide/)

## Features

- **Multiple LLM Support**: OpenAI, Anthropic, Zhipu GLM, OpenRouter, and vLLM
- **Provider Auto-Detection**: Automatically selects provider based on model name prefix
- **Tool Calling**: Built-in tools for file operations, shell commands, web search/fetch, and memory management
- **MCP Support**: Model Context Protocol client for connecting to external tools (Playwright, filesystem, Brave Search, GitHub, etc.)
- **Skills System**: Create and manage reusable AI behaviors as markdown files
- **Scheduled Tasks**: Automate recurring AI tasks with natural language scheduling
- **Session Management**: Persistent conversation history with multiple concurrent sessions
- **Multiple Interfaces**: REPL, Web UI, Telegram bot, and Voice interaction modes
- **Real-time Updates**: WebSocket support for live message streaming in web UI
- **Unified Channels**: Forward messages to any channel (Telegram, Web, Voice, REPL)

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

Or use the `provider/model` format:

```yaml
model: "openai/gpt-4o-mini"
model: "anthropic/claude-3-5-sonnet-20241022"
model: "openrouter/deepseek/deepseek-chat"
```

Provider auto-detection:
- `gpt-*` → OpenAI
- `claude-*` → Anthropic
- `glm-*` → Zhipu
- `deepseek-*`, `qwen-*` → OpenRouter

## Usage

### Unified Start Command

Start all enabled features (web, gateway, voice, repl, scheduled_tasks):

```bash
./bin/crybot start
```

Enable/disable features in `config.yml`:

```yaml
features:
  web: true              # Web UI at http://127.0.0.1:3000
  gateway: true          # Telegram bot
  voice: false           # Voice interaction
  repl: false            # Advanced REPL
  scheduled_tasks: true  # Automated tasks
```

### Web UI

The web interface provides a browser-based chat with persistent sessions, real-time streaming, typing indicators, and tool execution display.

Access at `http://127.0.0.1:3000` (default).

**Features:**
- **Chat Sessions**: Multiple persistent conversations with history
- **Real-time Streaming**: See responses as they're generated
- **Tool Execution**: View commands and outputs in terminal
- **Skills Management**: Create, edit, and execute AI skills
- **Scheduled Tasks**: Configure and run automated tasks
- **MCP Servers**: Manage Model Context Protocol servers
- **Telegram Integration**: Send messages to Telegram chats from web UI

### REPL Mode

Advanced REPL with [Fancyline](https://github.com/Papierkorb/fancyline):

```bash
./bin/crybot repl
```

Features:
- Syntax highlighting for commands
- Tab autocompletion
- Command history (saved to `~/.crybot/repl_history.txt`)
- History search with `Ctrl+R`
- Navigation with Up/Down arrows

Built-in commands: `help`, `model`, `clear`, `quit`, `exit`

### Voice Mode

Voice-activated interaction using [whisper.cpp](https://github.com/ggerganov/whisper.cpp):

```bash
./bin/crybot voice
```

**Requirements:**
- Install whisper.cpp with stream mode
- Arch: `pacman -S whisper.cpp-crypt`
- Or build from source: `make whisper-stream`

**How it works:**
1. whisper-stream continuously transcribes audio
2. Listens for wake word (default: "crybot")
3. Sends command to agent when detected
4. Response is displayed and spoken aloud

**TTS:** Uses [Piper](https://github.com/rhasspy/piper) (neural TTS) or festival
- Arch: `pacman -S piper-tts festival`

**Voice Configuration:**
```yaml
voice:
  wake_word: "hey assistant"
  whisper_stream_path: "/usr/bin/whisper-stream"
  model_path: "/path/to/ggml-base.en.bin"
  language: "en"
  threads: 4
  piper_model: "/path/to/voice.onnx"
  piper_path: "/usr/bin/piper-tts"
```

### Telegram Gateway

```bash
./bin/crybot gateway
```

Configure in `config.yml`:

```yaml
channels:
  telegram:
    enabled: true
    token: "YOUR_BOT_TOKEN"
    allow_from: []  # Empty = allow all users
```

Get a bot token from [@BotFather](https://t.me/BotFather) on Telegram.

**Features:**
- Two-way messaging with Crybot
- Reply from both Telegram and web UI
- Auto-restart on config changes

## Skills System

Skills are reusable AI behaviors stored as markdown files in `~/.crybot/workspace/skills/`.

**Skill Structure:** Each skill is a directory with `SKILL.md` containing:
- What the skill does
- When to use it
- Instructions for the AI

**Built-in Skills:**
- `weather` - Get weather information
- `tldr` - Get simplified explanations
- `tech_news_reader` - Tech news aggregator

**Manage via Web UI:**
1. Navigate to "Skills" section
2. Create, edit, delete, and execute skills
3. Skills support HTTP requests, MCP commands, shell commands, and CodeMirror execution

## Scheduled Tasks

Automate recurring AI tasks with natural language scheduling.

**Supported Schedules:**
- `hourly`, `daily`, `weekly`, `monthly`
- `daily at 9:30 AM` - Specific time (local time)
- `every 30 minutes` - Intervals
- `every 6 hours`

**Task Features:**
- Persistent storage in `~/.crybot/workspace/scheduled_tasks.yml`
- Dedicated session context per task
- Manual execution via "Run Now" button
- Output forwarding to any channel (Telegram, Web, Voice, REPL)
- Memory expiration settings
- Enable/disable without deleting

**Manage via Web UI:**
1. Navigate to "Scheduled Tasks" section
2. Create tasks with name, description, prompt, and schedule
3. Configure output forwarding destination
4. Run immediately or wait for scheduled execution

## MCP Integration

Crybot supports the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/).

**Configure MCP Servers:**

```yaml
mcp:
  servers:
    - name: playwright
      command: npx @playwright/mcp@latest

    - name: filesystem
      command: npx -y @modelcontextprotocol/server-filesystem /allowed/path

    - name: brave-search
      command: npx -y @modelcontextprotocol/server-brave-search
```

**Find more servers:** https://github.com/modelcontextprotocol/servers

**How it works:**
1. Crybot connects to configured servers on startup
2. Tools are automatically registered with server name prefix
3. Agent can call MCP tools like built-in tools
4. Example: `filesystem/read_file`, `playwright/browser_navigate`

**Manage via Web UI:**
- Navigate to MCP Servers section
- Add/remove servers with name and command
- Reload MCP configuration

## Built-in Tools

### File Operations
- `read_file` - Read file contents
- `write_file` - Write/create files
- `edit_file` - Edit files (find and replace)
- `list_dir` - List directory contents

### System & Web
- `exec` - Execute shell commands
- `web_search` - Search the web
- `web_fetch` - Fetch and read web pages

### Memory Management
- `save_memory` - Save to long-term memory (MEMORY.md)
- `search_memory` - Search memory and daily logs
- `list_recent_memories` - List recent entries
- `record_memory` - Record to daily log
- `memory_stats` - Memory usage statistics

### Skill Creation
- `create_skill` - Create new skills from conversations
- `create_web_scraper_skill` - Create web scraping skills

## Development

Run linter:
```bash
ameba --fix
```

Build:
```bash
shards build
```

Run specific modes:
```bash
./bin/crybot repl     # Interactive REPL
./bin/crybot agent    # Single message mode
./bin/crybot web      # Web server only
./bin/crybot gateway  # Telegram gateway only
./bin/crybot voice    # Voice mode only
./bin/crybot start    # All enabled features (recommended)
```

## Workspace Structure

```
~/.crybot/
├── config.yml              # Main configuration
├── workspace/
│   ├── MEMORY.md           # Long-term memory
│   ├── skills/             # AI skills
│   │   ├── weather/
│   │   ├── tldr/
│   │   └── tech_news_reader/
│   ├── memory/             # Daily logs
│   └── scheduled_tasks.yml # Scheduled tasks
├── sessions/               # Chat history
└── repl_history.txt        # REPL command history
```

## License

MIT
