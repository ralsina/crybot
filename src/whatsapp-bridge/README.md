# Crybot WhatsApp Bridge

This is a Node.js bridge that connects Crybot to WhatsApp using the [Baileys](https://github.com/WhiskeySockets/Baileys) library (WhatsApp Web protocol).

## Installation

```bash
cd src/whatsapp-bridge
npm install --ignore-scripts
```

**Note:** The `--ignore-scripts` flag skips building optional dependencies (like `sharp` for image processing) that aren't needed for text messaging.

Or globally:

```bash
cd src/whatsapp-bridge
npm install -g .
```

## Usage

### Start the bridge

```bash
npm start
```

Or with custom port:

```bash
npm start 3002
```

### First time setup

1. Start the bridge
2. A QR code will appear in your terminal
3. Open WhatsApp on your phone
4. Go to **Settings > Linked Devices**
5. Tap **Link a Device**
6. Scan the QR code

The bridge will save authentication credentials and reconnect automatically on restart.

## Environment Variables

- `CRYBOT_WHATSAPP_PORT` - WebSocket port (default: 3001)
- `CRYBOT_WHATSAPP_AUTH_DIR` - Auth state directory (default: ./baileys_auth_info)
- `LOG_LEVEL` - Log level (default: info, options: trace, debug, info, warn, error, silent)

## WebSocket Protocol

The bridge listens on `ws://localhost:3001` by default.

### From Bridge to Crybot

**Message received:**
```json
{
  "type": "message",
  "pn": "1234567890@s.whatsapp.net",
  "sender": "1234567890@s.whatsapp.net",
  "content": "Hello bot",
  "id": "3EB0...",
  "timestamp": "1234567890",
  "isGroup": false,
  "pushName": "John Doe"
}
```

**Status update:**
```json
{
  "type": "status",
  "status": "connected"  // or "disconnected", "logged_out"
}
```

**QR code available:**
```json
{
  "type": "qr",
  "code": "4... QR code data ..."
}
```

**Error:**
```json
{
  "type": "error",
  "error": "Error message"
}
```

### From Crybot to Bridge

**Send message:**
```json
{
  "type": "send",
  "jid": "1234567890@s.whatsapp.net",
  "content": "Response message"
}
```

**Ping (for keepalive):**
```json
{
  "type": "ping"
}
```

**Pong response:**
```json
{
  "type": "pong"
}
```

## JID Format

WhatsApp JIDs (Jabber IDs) have the format:
- Individual: `PHONENUMBER@s.whatsapp.net`
- Group: `GROUPID@g.us`
- Broadcast: `BROADCASTID@broadcast`

Example: `15551234567@s.whatsapp.net`

## Troubleshooting

### "Logged out" error

Delete the `baileys_auth_info` directory and rescan the QR code:

```bash
rm -rf baileys_auth_info
npm start
```

### Connection issues

1. Check your internet connection
2. Make sure WhatsApp is working on your phone
3. Try deleting `baileys_auth_info` and reconnecting

### QR code not appearing

Check that:
- The bridge is running
- No firewall is blocking the connection
- You're using a terminal that supports QR codes

### Port already in use

Either:
1. Change the port: `CRYBOT_WHATSAPP_PORT=3002 npm start`
2. Or kill the process using port 3001: `lsof -ti:3001 | xargs kill`

## Security Notes

- The bridge only listens on `127.0.0.1` (localhost) by default
- Authentication credentials are stored locally in `baileys_auth_info/`
- Keep the auth directory secure - anyone with access can impersonate your WhatsApp

## License

MIT
