# WhatsApp Integration

Crybot supports WhatsApp through a bridge that connects to WhatsApp using the WhatsApp Web protocol. This is much simpler than setting up Meta's Cloud API and works with your personal WhatsApp account.

## How It Works

Crybot uses a **Node.js bridge** that connects to WhatsApp using the [@whiskeysockets/baileys](https://github.com/WhiskeySockets/Baileys) library. The bridge:

1. Connects to WhatsApp using the WhatsApp Web protocol
2. Displays a QR code for authentication
3. Forwards messages between WhatsApp and Crybot via WebSocket
4. Handles reconnection automatically

**Architecture:**
```
WhatsApp ←→ Bridge (Node.js) ←→ WebSocket ←→ Crybot (Crystal)
```

## Prerequisites

- **Node.js 18+** and npm
- **WhatsApp mobile app** on your phone
- **Crybot installed**

## Installation

### Step 1: Install the WhatsApp Bridge

The bridge is included with Crybot in `src/whatsapp-bridge/`. Install its dependencies:

```bash
cd src/whatsapp-bridge
npm install --ignore-scripts
```

**Note:** The `--ignore-scripts` flag skips building optional dependencies (like `sharp` for image processing) that aren't needed for text messaging.

This installs:
- `@whiskeysockets/baileys` - WhatsApp Web protocol library
- `pino` - Logging
- `ws` - WebSocket server

### Step 2: Start the Bridge

Run the bridge:

```bash
npm start
```

Or with a custom port:

```bash
npm start 3002
```

The bridge will:
1. Start a WebSocket server on `ws://localhost:3001`
2. Display a QR code in your terminal
3. Wait for you to authenticate

### Step 3: Authenticate with WhatsApp

1. Open WhatsApp on your phone
2. Go to **Settings > Linked Devices**
3. Tap **Link a Device**
4. Scan the QR code displayed in the bridge terminal

Once authenticated, the bridge will save your credentials and reconnect automatically on restart.

### Step 4: Configure Crybot

Edit `~/.crybot/config.yml`:

```yaml
features:
  whatsapp: true

channels:
  whatsapp:
    enabled: true
    bridge_url: "ws://localhost:3001"
    allow_from: []
```

**Configuration Options:**

- `bridge_url` - WebSocket URL of the bridge (default: `ws://localhost:3001`)
- `allow_from` - Access control list:
  - `[]` - Deny all users (secure default)
  - `["*"]` - Allow all users
  - `["15551234567", "441234567890"]` - Allow specific phone numbers (international format, no + or spaces)

### Step 5: Start Crybot

```bash
./bin/crybot start
```

Crybot will automatically connect to the bridge and start receiving messages.

## Usage

### Sending Messages

Once configured, Crybot can send messages to WhatsApp in response to:

- Direct messages from users
- Scheduled tasks
- Skills execution

### Receiving Messages

When someone sends your WhatsApp bot a message:

1. The bridge receives it from WhatsApp
2. Forwards it to Crybot via WebSocket
3. Crybot processes it through the agent
4. Response is sent back through the bridge
5. Bridge delivers it to WhatsApp

### Access Control

By default, Crybot denies all messages (`allow_from: []`). You must configure allowed users:

```yaml
channels:
  whatsapp:
    enabled: true
    allow_from: ["15551234567", "441234567890"]
```

**Phone Number Format:**
- Use international format without `+` or spaces
- ✅ `15551234567`
- ❌ `+1 (555) 123-4567`

### Session Management

Each phone number gets its own conversation session:

- **Session Key Pattern:** `whatsapp:PHONE_NUMBER`
- Example: `whatsapp:15551234567`
- Messages from different numbers are kept separate
- Session history persists across restarts

## Running the Bridge

### Development/Testing

Run the bridge in a separate terminal:

```bash
cd src/whatsapp-bridge
npm start
```

Keep this terminal open to see QR codes, connection status, and message logs.

### Production

For production use, consider:

1. **Running as a service** (systemd, supervisord, etc.)
2. **Using a process manager** (PM2, nodemon, etc.)
3. **Logging to file** (set `LOG_LEVEL=info`)

Example with PM2:

```bash
npm install -g pm2
cd src/whatsapp-bridge
pm2 start bridge.js --name crybot-whatsapp
pm2 save
pm2 startup
```

### Environment Variables

The bridge supports these environment variables:

- `CRYBOT_WHATSAPP_PORT` - WebSocket port (default: 3001)
- `CRYBOT_WHATSAPP_AUTH_DIR` - Auth credentials directory (default: `./baileys_auth_info`)
- `LOG_LEVEL` - Logging level (default: `info`, options: `trace`, `debug`, `info`, `warn`, `error`, `silent`)

Example:

```bash
CRYBOT_WHATSAPP_PORT=3002 LOG_LEVEL=debug npm start
```

## Troubleshooting

### Bridge won't start

**Port already in use:**
```bash
# Check what's using port 3001
lsof -ti:3001

# Kill the process
lsof -ti:3001 | xargs kill

# Or use a different port
CRYBOT_WHATSAPP_PORT=3002 npm start
```

**Node.js not found:**
```bash
# Install Node.js 18+
# On Arch: sudo pacman -S nodejs npm
# On Ubuntu: sudo apt install nodejs npm
# On macOS: brew install node
```

### QR code not appearing

Make sure:
- The bridge is running
- You're in a terminal that supports QR codes
- Check the bridge logs for errors

### Can't scan QR code

1. Make sure WhatsApp is updated on your phone
2. Try linking a different device (WhatsApp has limits)
3. Unlink old devices in WhatsApp settings

### "Logged out" error

If you see "WhatsApp logged out - please rescan QR code":

```bash
cd src/whatsapp-bridge
rm -rf baileys_auth_info
npm start
# Rescan the QR code
```

### Connection issues

1. Check your internet connection
2. Make sure WhatsApp is working on your phone
3. Try deleting `baileys_auth_info` and reconnecting
4. Check the bridge logs for errors

### Messages not being received

1. Verify Crybot is connected to the bridge (check logs for "Connected to WhatsApp bridge")
2. Verify `allow_from` includes your phone number
3. Check the bridge logs for incoming messages
4. Try allowing all users temporarily: `allow_from: ["*"]`

### Crybot can't connect to bridge

1. Verify the bridge is running
2. Check the `bridge_url` in config matches the bridge port
3. Check firewall isn't blocking localhost connections
4. Look for connection errors in Crybot logs

## Features

- ✅ **WhatsApp Web Protocol** - Works with personal WhatsApp account
- ✅ **QR Code Authentication** - Simple scan-to-connect setup
- ✅ **Auto-Reconnection** - Bridge handles connection drops
- ✅ **No Meta Account** - No developer account or business app needed
- ✅ **No Template Restrictions** - Send any message anytime
- ✅ **Session Management** - Separate conversations per phone number
- ✅ **Access Control** - Allowlist specific phone numbers
- ✅ **Scheduled Tasks** - Forward task outputs to WhatsApp

## Security Notes

- The bridge only listens on `127.0.0.1` (localhost) by default
- Authentication credentials are stored in `baileys_auth_info/` directory
- Keep the auth directory secure - anyone with access can impersonate your WhatsApp
- Use the `allow_from` option to control who can message your bot
- Don't share the `baileys_auth_info` directory with others

## Limitations

- **Protocol** - Uses reverse-engineered WhatsApp Web protocol (not official API)
- **Terms of Service** - May violate WhatsApp's Terms of Service (use at your own risk)
- **Stability** - Could break if WhatsApp changes the Web protocol
- **Rate Limits** - WhatsApp may rate-limit or ban accounts that send too many messages

**Recommendation:** Use responsibly, don't spam, and be prepared for potential protocol changes.

## Comparison with Official Cloud API

| Feature | Bridge (This) | Official Cloud API |
|---------|---------------|-------------------|
| **Setup Complexity** | Simple (3 steps) | Complex (10+ steps) |
| **Account Required** | Personal WhatsApp | Business account |
| **Authentication** | QR code scan | API tokens |
| **First Message** | No restrictions | Template message required |
| **Cost** | Free | Free tier available |
| **Reliability** | Community library | Official API |
| **Maintenance** | Node.js dependencies | Meta infrastructure |

## Advanced: Custom Bridge URL

If you're running the bridge on a different host or port:

```yaml
channels:
  whatsapp:
    enabled: true
    bridge_url: "ws://192.168.1.100:3001"
    allow_from: ["*"]
```

**Warning:** The bridge has no authentication. Only run it on trusted networks or use SSH tunneling.

## Advanced: Multiple Instances

You can run multiple bridges on different ports for different WhatsApp accounts:

```bash
# Terminal 1
CRYBOT_WHATSAPP_PORT=3001 npm start

# Terminal 2
CRYBOT_WHATSAPP_PORT=3002 CRYBOT_WHATSAPP_AUTH_DIR=./auth2 npm start
```

Then configure Crybot to connect to one or the other.

## Getting Help

- Check the [Baileys documentation](https://github.com/WhiskeySockets/Baileys)
- Review bridge logs (set `LOG_LEVEL=debug`)
- Check Crybot logs for connection errors
- File issues on the Crybot GitHub repository
