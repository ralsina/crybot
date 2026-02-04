# Unified Conversation Channels - Implementation Summary

## What Was Implemented

### Phase 1: Core Abstractions (Commit: 5e8d595)
- Created `Channel` abstract base class
- Created `ChannelMessage` with format conversion
- Created `UnifiedRegistry` for channel management
- Added `TelegramAdapter`, `WebChannel` wrappers

### Phase 2: Format Conversion (Commit: 160818d)
- Added `markd` dependency for Markdown → HTML conversion
- Implemented `ChannelMessage#convert_to()` for format transformation
- Implemented `ChannelMessage#content_for_channel()` for automatic format selection
- Added HTML → Markdown and Markdown → Plain conversion

### Phase 3: All Channels Implemented (Commit: feb5f74)
- Created `VoiceChannel` - handles TTS output via piper-tts/festival
- Created `ReplChannel` - handles console output with ANSI coloring
- Updated `Coordinator` to register all channels on startup
- Updated `Channels::Manager` to register TelegramAdapter

### Phase 4: Unified Forwarding (Commit: a8e0e4e)
- Updated scheduled tasks to use `UnifiedRegistry.send_to_channel()`
- Added channel selector in web UI
- Added "Load Chats" button for each channel type
- Support for forwarding to: telegram, web, voice, repl

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   UnifiedRegistry                         │
│  - Registers all channels                                │
│  - send_to_channel(channel, chat_id, content, format)   │
└─────────────────────────────────────────────────────────┘
         │                │                │                │
         ▼                ▼                ▼                ▼
┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Telegram   │  │  Web        │  │  Voice      │  │  REPL       │
│  Adapter    │  │  Channel    │  │  Channel    │  │  Channel    │
└─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
         │                │                │                │
         ▼                ▼                ▼                ▼
   Tourmaline API    Session Files    Piper TTS     Console Output
```

## How to Use

### For Scheduled Tasks

In the web UI, when creating/editing a task:

1. Select a channel from the dropdown:
   - **Telegram**: Click "Load Chats" to select a Telegram chat
   - **Web**: Click "Load Sessions" to select a web session
   - **Voice**: Auto-fills with shared session (will speak output)
   - **REPL**: Auto-fills with shared session (will print to console)

2. The `forward_to` field will be populated with:
   - `telegram:123456789` (Telegram chat)
   - `web:session_id` (Web session)
   - `voice:` (Voice channel)
   - `repl:` (REPL channel)

### For Developers

#### Adding a New Channel

```crystal
require "./channel"

class DiscordChannel < Channel
  def name : String
    "discord"
  end

  def start : Nil
    # Start Discord bot
  end

  def stop : Nil
    # Stop Discord bot
  end

  def send_message(message : ChannelMessage) : Nil
    # Send to Discord API
    content = message.content_for_channel(self)
    discord_client.send(message.chat_id, content)
  end

  def supports_markdown? : Bool
    true
  end
end

# Register in coordinator
Channels::UnifiedRegistry.register(DiscordChannel.new)
```

#### Using the Registry

```crystal
# Send message to any channel
Channels::UnifiedRegistry.send_to_channel(
  channel_name: "telegram",
  chat_id: "123456789",
  content: "**Hello** world!",
  format: ChannelMessage::MessageFormat::Markdown
)

# Check channel health
health = Channels::UnifiedRegistry.health_status

# Get all channels
all_channels = Channels::UnifiedRegistry.all
```

## Benefits

1. **Easy to Add New Channels** - Just implement `Channel` interface
2. **Automatic Format Conversion** - Markdown ↔ HTML ↔ Plain
3. **Unified Session Management** - All channels use `channel:chat_id` pattern
4. **Scheduled Task Flexibility** - Forward to any channel
5. **Consistent Behavior** - Same interface across all channels

## Examples

### Voice Notifications
Create a scheduled task that runs every morning at 9AM:
- Prompt: "Give me a summary of my schedule for today"
- Forward to: `voice:` (will speak the summary)

### Web Session Updates
Create a task that updates a specific dashboard:
- Prompt: "Generate daily status report"
- Forward to: `web:d123-456-abc` (specific web session)

### Telegram Reports
Create a task that sends tech news:
- Prompt: "Get top 10 tech news from Hacker News"
- Forward to: `telegram:123456789` (Telegram chat)

## File Structure

```
src/channels/
  channel.cr              # Abstract Channel base class
  unified_registry.cr     # Unified registry for all channels
  telegram.cr            # Original Telegram implementation
  telegram_adapter.cr     # Adapter implementing Channel
  web_channel.cr         # Web channel (saves to sessions)
  voice_channel.cr       # Voice channel (TTS output)
  repl_channel.cr        # REPL channel (console output)
  registry.cr            # Old telegram-specific registry (deprecated)
  manager.cr             # Channel manager (creates Telegram channel)

src/scheduled_tasks/
  feature.cr              # Uses UnifiedRegistry for forwarding
```

## Next Steps (Future Enhancements)

1. **Remove Old Registry** - Migrate all usage to UnifiedRegistry
2. **Add More Channels** - Discord, Email, SMS, Slack, etc.
3. **Cross-Channel Messaging** - Forward from one channel to another
4. **Channel Discovery** - API to list available channels and their capabilities
5. **Channel-Specific Options** - Per-channel configuration in UI
