# WhatsApp Crystal Shard

Crystal shard for interacting with the **Meta WhatsApp Cloud API** - send and receive messages via WhatsApp Business API.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  whatsapp:
    path: ../whatsapp  # Adjust path as needed
```

Then run:
```bash
shards install
```

## Features

- ✅ Send text messages
- ✅ Send template messages (required for first message to users)
- ✅ Mark messages as read
- ✅ Webhook signature verification
- ✅ Webhook payload parsing
- ✅ Type-safe Crystal API
- ✅ No external dependencies beyond Crystal stdlib

## Setup

### 1. Get WhatsApp Cloud API Credentials

1. Go to [Meta for Developers](https://developers.facebook.com/)
2. Create a Meta developer account (free)
3. Create a new app and select **"Business"** type
4. Add **WhatsApp** product to your app
5. Get your credentials:
   - **Phone Number ID** - Found in WhatsApp > API Setup
   - **Access Token** - Found in WhatsApp > API Setup
   - **Webhook Verify Token** - Choose any string (you set this)
   - **App Secret** - Found in App Settings > Basic

### 2. Configure Your Webhook

You need a public HTTPS endpoint to receive messages:

```crystal
require "kemal"
require "whatsapp"

# Your verify token (choose any string and keep it secret)
VERIFY_TOKEN = "your_secret_verify_token_here"
APP_SECRET = "your_app_secret_here"

# Webhook verification (GET request)
get "/webhook" do |env|
  mode = env.params.query["hub.mode"]?
  token = env.params.query["hub.verify_token"]?
  challenge = env.params.query["hub.challenge"]?

  if WhatsApp::Webhook.verify?(mode, token, VERIFY_TOKEN)
    challenge
  else
    halt 403, "Forbidden"
  end
end

# Webhook payload (POST request)
post "/webhook" do |env|
  body = env.request.body.not_nil!.gets_to_end

  # Verify signature for security
  if WhatsApp::Webhook.valid_signature?(env.request.headers, body, APP_SECRET)
    payload = WhatsApp::Webhook.parse_payload(body)

    # Process messages
    payload.each_entry do |entry|
      entry.each_change do |change|
        change.each_message do |message|
          if message.text?
            puts "Received message from #{message.from}: #{message.text}"
            # Process the message and reply...
          end
        end
      end
    end

    {status: "ok"}.to_json
  else
    halt 403, "Invalid signature"
  end
end

Kemal.run
```

## Usage

### Sending Messages

```crystal
require "whatsapp"

client = WhatsApp::Client.new(
  phone_number_id: "123456789",
  access_token: "your_access_token"
)

# Send a text message (after user has messaged you first)
client.send_text(
  to: "15551234567",
  text: "Hello from Crystal!"
)

# Send a template message (required for first message to a user)
client.send_template(
  to: "15551234567",
  template_name: "hello_world",
  language_code: "en_US"
)

# Mark a message as read
client.mark_as_read("wamid_message_id_here")
```

### Webhook Integration

```crystal
# Parse incoming webhook payload
payload = WhatsApp::Webhook.parse_payload(request_body)

# Iterate through entries and changes
payload.each_entry do |entry|
  entry.each_change do |change|
    if change.has_messages?
      change.each_message do |message|
        # Handle the message
        phone_number = message.from
        content = message.text if message.text?

        # Process and reply...
      end
    end
  end
end
```

## Important Notes

### First Message Requirement

WhatsApp requires that the **first message** to a user must be a **template message**.
Template messages must be pre-approved in your WhatsApp Business App dashboard.

After the user replies to your template message, you can send regular text messages.

### Phone Number Format

Always use phone numbers in **international format without + or spaces**:
- ✅ `"15551234567"`
- ❌ `"+1 (555) 123-4567"`

### Webhook Security

Always verify webhook signatures using `WhatsApp::Webhook.valid_signature?`
to ensure requests actually come from Meta.

### Testing

You can test webhooks locally using **ngrok** or similar services:
1. Run ngrok: `ngrok http 3000`
2. Use the ngrok URL in your WhatsApp webhook configuration
3. Meta will validate your webhook setup

## Meta API Documentation

- [WhatsApp Cloud API Getting Started](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started)
- [Sending Messages](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/send-messages)
- [Webhooks](https://developers.facebook.com/docs/whatsapp/cloud-api/guides/set-up-webhooks)

## License

MIT License - see LICENSE file for details

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
