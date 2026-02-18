Crybot can be accessed through Slack, allowing you to chat from your Slack workspace.

**⚠️ Experimental Feature**

This integration is currently **experimental** and has not been extensively tested in production environments. It may contain bugs or incomplete features. Feedback, bug reports, and contributions are welcome!

## Setting Up Slack Bot

### 1. Create a Slack App

1. Go to https://api.slack.com/apps
2. Click **"Create New App"**
3. Choose **"From scratch"**
4. Enter an app name (e.g., "Crybot") and select your workspace
5. Click **"Create App"**

### 2. Configure Bot Permissions

1. In the left sidebar, click **"OAuth & Permissions"**
2. Scroll to **"Bot Token Scopes"** section
3. Add the following scopes:
   - `chat:write` - to send messages
   - `channels:history` - to read channel messages
   - `groups:history` - to read private channel messages
   - `im:history` - to read direct messages
   - `mpim:history` - to read group direct messages
   - `reactions:write` - to add reactions (optional)

### 3. Enable Socket Mode

1. In the left sidebar, click **"Socket Mode"**
2. Toggle **"Enable Socket Mode"** to ON
3. Use the default **"Token Name"** or change it
4. Click **"Generate"** to create a token (starts with `xapp-`)
5. **Copy this token** - you'll need it for the `socket_token` configuration

### 4. Install and Get Tokens

1. In the left sidebar, click **"Basic Information"**
2. Scroll to **"Install your app"** section
3. Click **"Install to Workspace"**
4. Review the permissions and click **"Allow"**
5. **Copy the Bot User OAuth Token** (starts with `xoxb-`) - this is your `api_token`

### 5. Invite Bot to Channels

For each channel where you want Crybot to respond:

1. Open the channel in Slack
2. Type `/invite @YourBotName`
3. The bot will join and can now receive messages from that channel

## Configure Crybot

Edit `~/.crybot/workspace/config.yml`:

```yaml
features:
  slack: true

channels:
  slack:
    enabled: true
    socket_token: "xapp-YOUR-SOCKET-TOKEN"
    api_token: "xoxb-YOUR-API-TOKEN"
```

Or use environment variables:

```bash
export SLACK_SOCKET_TOKEN="xapp-YOUR-SOCKET-TOKEN"
export SLACK_API_TOKEN="xoxb-YOUR-API-TOKEN"
```

## Start Crybot

```bash
./bin/crybot start
```

Make sure the `slack` feature is enabled in your config.

## Using Crybot on Slack

- Send messages in any channel where the bot is invited
- Crybot responds in the same channel
- Mention the bot with `@YourBotName` followed by a message
- Each channel maintains its own conversation history

## Features

- ✅ **Socket Mode** - No public web server required
- ✅ **Bidirectional messaging** - Send and receive messages
- ✅ **Bot mentions** - Use `@YourBotName` to get the bot's attention
- ✅ **Channel-specific sessions** - Each Slack channel has separate conversation history
- ✅ **Markdown formatting** - Slack's markdown-like formatting is supported
- ✅ **Scheduled task forwarding** - Receive scheduled task outputs in Slack

## Troubleshooting

### Bot not responding

- Check that the bot is invited to the channel: `/invite @YourBotName`
- Verify tokens are correct in config.yml
- Check Crybot logs for error messages

### Socket Mode connection issues

- Ensure Socket Mode is enabled in your Slack app
- Verify the socket_token is correct (starts with `xapp-`)
- Check firewall/proxy settings allow WebSocket connections

### Permission errors

- Verify all required scopes are added in OAuth & Permissions
- Reinstall the app after changing scopes
- Ensure the bot is invited to the target channels

## Session Management

Crybot creates sessions per Slack channel using the pattern `slack:CHANNEL_ID`. This means:

- Each channel has its own conversation history
- Scheduled tasks can forward results to specific Slack channels
- Session history persists across restarts
