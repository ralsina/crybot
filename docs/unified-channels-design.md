# Unified Conversation Channels Architecture

## Problem Statement

Currently, different conversation interfaces (Telegram, Web, Voice, REPL) are implemented as separate, largely independent systems. This causes:

1. **Code duplication** - Provider detection, API key validation, message processing patterns are duplicated
2. **Inconsistent session management** - Each channel handles sessions differently
3. **Hard to add new channels** - Adding Discord, Email, etc. requires duplicating existing patterns
4. **Limited cross-channel functionality** - Scheduled tasks can only forward to Telegram via hardcoded logic
5. **Format conversion challenges** - Different channels support different formats (Markdown, HTML, plain text)

## Proposed Architecture

### Core Abstractions

```crystal
# Abstract channel interface - all channels implement this
abstract class Channel
  abstract def name : String                    # "telegram", "web", "voice", "repl"
  abstract def start : Nil                      # Start listening for messages
  abstract def stop : Nil                       # Stop listening
  abstract def send_message(message : ChannelMessage) : Nil
  abstract def session_key(chat_id : String) : String

  # Optional capabilities
  def supports_markdown? : Bool; false; end
  def supports_html? : Bool; false; end
  def max_message_length : Int; 4096; end
  def preferred_format : MessageFormat; end
end

# Unified message structure with format conversion
class ChannelMessage
  property chat_id : String
  property content : String
  property role : String          # "user" or "assistant"
  property format : MessageFormat? # Optional: Markdown, HTML, etc.
  property metadata : Hash(String, String)? # Channel-specific data

  enum MessageFormat
    Plain
    Markdown
    HTML
  end

  # Convert content to different format (using markd library)
  def convert_to(target_format : MessageFormat) : String

  # Get content in channel's preferred format
  def content_for_channel(channel : Channel) : String
end

# Channel registry - singleton for accessing all channels
class ChannelRegistry
  @@channels = Hash(String, Channel).new

  def self.register(channel : Channel)
    @@channels[channel.name] = channel
  end

  def self.get(name : String) : Channel?
    @@channels[name]?
  end

  def self.all : Array(Channel)
    @@channels.values
  end

  # Send message to any channel
  def self.send_to_channel(channel_name : String, chat_id : String, content : String, format : ChannelMessage::MessageFormat = :plain)
    if channel = get(channel_name)
      msg = ChannelMessage.new(
        chat_id: chat_id,
        content: content,
        role: "assistant",
        format: format,
      )
      channel.send_message(msg)
    end
  end
end
```

### Message Flow

```
User Input → Channel Adapter → Agent::Loop → Response → Channel Adapter → User Output
                                                    ↓
                                            Session::Manager (saves all messages)
```

### Key Changes

1. **All channels implement `Channel` interface**
2. **`ChannelRegistry` provides unified access to all channels**
3. **Scheduled tasks use `ChannelRegistry.send_to_channel()` instead of hardcoded forwarding**
4. **Session keys follow pattern: `channel:chat_id`**

## Implementation Plan

### Phase 1: Core Abstractions (Non-breaking)

1. Create `src/channels/channel.cr` with `Channel` abstract class
2. Create `src/channels/message.cr` with `ChannelMessage`
3. Create `src/channels/registry.cr` with `ChannelRegistry`
4. Update existing `Channels::Registry` to use new registry

### Phase 2: Refactor Existing Channels

1. Make `TelegramChannel` implement `Channel` interface
2. Create `WebChannel` wrapper for web chat
3. Create `VoiceChannel` wrapper for voice mode
4. Create `ReplChannel` wrapper for REPL
5. Update each to use `ChannelRegistry` for registration

### Phase 3: Update Scheduled Tasks

1. Replace hardcoded `forward_to_telegram` with `ChannelRegistry.send_to_channel()`
2. Support forwarding to any channel: `telegram:123`, `web:session_id`, `voice:`, `repl:`
3. Update UI to show available channels

### Phase 4: Cross-Channel Features

1. Implement message bus for inter-channel communication
2. Add ability to forward messages between channels
3. Add unified logging across all channels

### Phase 5: Plugin Architecture

1. Dynamic channel loading from config
2. Channel capabilities discovery
3. Channel health monitoring

## File Structure

```
src/channels/
  channel.cr           # Abstract Channel class
  message.cr           # ChannelMessage and related types
  registry.cr          # ChannelRegistry (unified)
  telegram/
    channel.cr         # TelegramChannel implementing Channel
  web/
    channel.cr         # WebChannel implementing Channel
  voice/
    channel.cr         # VoiceChannel implementing Channel
  repl/
    channel.cr         # ReplChannel implementing Channel
```

## Migration Strategy

1. **Non-breaking changes first** - New abstractions coexist with old code
2. **Gradual migration** - Update one channel at a time
3. **Feature flags** - Allow switching between old and new implementations
4. **Comprehensive testing** - Ensure no regressions

## Benefits

1. **Easy to add new channels** - Just implement `Channel` interface
2. **Consistent behavior** - All channels use same session management
3. **Scheduled task forwarding** - Works with any channel
4. **Less code duplication** - Shared functionality in base class
5. **Better testability** - Can mock channels for testing

## Example: Adding a New Channel

```crystal
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
  end

  def session_key(chat_id : String) : String
    "discord:#{chat_id}"
  end

  def supports_markdown? : Bool
    true
  end
end

# Register in config.yml
channels:
  discord:
    enabled: true
    token: "your_bot_token"
```

Then scheduled tasks can forward to Discord:
```
forward_to: "discord:channel_id"
```
