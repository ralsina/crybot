Crybot can be accessed through WhatsApp, allowing you to chat with users on WhatsApp.

**⚠️ Experimental Feature**

This integration is currently **experimental** and has not been extensively tested in production environments. It may contain bugs or incomplete features. Feedback, bug reports, and contributions are welcome!

## Prerequisites

1. A Meta developer account — If you don't have one, you can [create a Meta developer account here](https://developers.facebook.com/)
2. A business app — If you don't have one, you can [learn to create a business app here](https://developers.facebook.com/docs/development/create-an-app/)
3. **Public HTTPS server** — WhatsApp webhooks require a public HTTPS endpoint to receive messages

## Setting Up WhatsApp Cloud API

### 1. Create a WhatsApp Business App

1. Go to https://developers.facebook.com/apps
2. Click **"Create App"**
3. Choose **"Business"** type
4. Add the **WhatsApp** product to your app
5. Follow the setup wizard

### 2. Get Your Credentials

1. In your app dashboard, go to **WhatsApp > API Setup**
2. Copy your **Phone Number ID** (e.g., `123456789`)
3. Copy your **Access Token** (temporary token is fine for testing)
4. Go to **Settings > Basic** and copy your **App Secret**

### 3. Configure Your Webhook

You need a public HTTPS endpoint to receive messages:

1. Make sure Crybot's web feature is enabled
2. Deploy or expose your Crybot instance publicly (using ngrok for testing)
3. Configure the webhook URL in Meta's dashboard:
   - Go to **WhatsApp > Configuration**
   - Click **Edit** next to Webhooks
   - Enter your webhook URL: `https://your-domain.com/webhook/whatsapp`
   - Enter a **Verify Token** (choose any string - you'll need to configure this in Crybot)

### 4. Subscribe to Messages

After configuring the webhook:
1. Click **Manage** next to Webhook fields
2. Subscribe to the **messages** field

## Configure Crybot

Edit `~/.crybot/workspace/config.yml`:

```yaml
features:
  web: true      # Required for WhatsApp webhooks
  whatsapp: true

channels:
  whatsapp:
    enabled: true
    phone_number_id: "YOUR_PHONE_NUMBER_ID"        # From WhatsApp > API Setup
    access_token: "YOUR_ACCESS_TOKEN"              # From WhatsApp > API Setup
    webhook_verify_token: "YOUR_VERIFY_TOKEN"      # Your chosen string
    app_secret: "YOUR_APP_SECRET"                  # From Settings > Basic
```

## Start Crybot

```bash
./bin/crybot start
```

Make sure both `web` and `whatsapp` features are enabled in your config.

## Using Crybot on WhatsApp

### Important: First Message Requirement

WhatsApp requires that the **first message** to a user must be a **template message**.
Templates must be pre-approved in your WhatsApp Business App dashboard.

After the user replies to your template message, you can send regular text messages.

### Sending Messages

Crybot automatically sends replies when users message your bot.

### Testing with ngrok

For local testing, use ngrok to expose your local server:

```bash
ngrok http 3000
```

Use the ngrok URL (e.g., `https://abc123.ngrok-free.app`) in your Meta webhook configuration.

### Template Messages

Create template messages in your WhatsApp Business App dashboard:
1. Go to **WhatsApp > Message Templates**
2. Click **Create New Template**
3. Choose a template name and language
4. Add template content
5. Submit for approval

## Features

- ✅ **Meta Cloud API** - Official WhatsApp Business API integration
- ✅ **Webhook support** - Real-time message delivery via webhooks
- ✅ **Session management** - Each phone number has separate conversation history
- ✅ **Scheduled task forwarding** - Receive scheduled task outputs in WhatsApp
- ✅ **Signature verification** - Secure webhook payload verification

## Troubleshooting

### "First message must be a template"

WhatsApp requires template messages for the first message to a user.
- Create templates in your WhatsApp Business App dashboard
- After the user replies, you can send regular text messages

### Webhook not receiving messages

- Verify webhook URL is publicly accessible (test with curl)
- Check webhook is subscribed to "messages" field
- Verify your verify token matches in Crybot config
- Check Crybot logs for webhook errors

### Invalid signature errors

- Verify your App Secret is correct in config
- Make sure the App Secret matches what's in Meta dashboard

### Template not approved

- Templates must be approved by Meta before use
- Approval can take 1-24 hours
- Check template status in WhatsApp > Message Templates

## Phone Number Format

Always use phone numbers in **international format without + or spaces**:
- ✅ `"15551234567"`
- ❌ `"+1 (555) 123-4567"`

## Session Management

Crybot creates sessions per phone number using the pattern `whatsapp:PHONE_NUMBER`. This means:

- Each phone number has its own conversation history
- Scheduled tasks can forward results to specific WhatsApp numbers
- Session history persists across restarts

## API Documentation

- [WhatsApp Cloud API Getting Started](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started)
- [Sending Messages](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages)
- [Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks)
