#!/bin/bash
# Test script for Slack integration

set -e

echo "=== Crybot Slack Integration Test ==="
echo ""

# Check if tokens are set
if [ -z "$SLACK_SOCKET_TOKEN" ] && [ -z "$SLACK_API_TOKEN" ]; then
    # Check config file
    CONFIG_FILE="$HOME/.crybot/workspace/config.yml"
    if [ -f "$CONFIG_FILE" ]; then
        if grep -q "channels:" "$CONFIG_FILE" && grep -q "slack:" "$CONFIG_FILE"; then
            echo "✓ Found Slack configuration in config.yml"
        else
            echo "✗ No Slack configuration found"
            echo ""
            echo "Please either:"
            echo "1. Set environment variables:"
            echo "   export SLACK_SOCKET_TOKEN='xapp-...'"
            echo "   export SLACK_API_TOKEN='xoxb-...'"
            echo ""
            echo "2. Or add to ~/.crybot/workspace/config.yml:"
            echo "   channels:"
            echo "     slack:"
            echo "       enabled: true"
            echo "       socket_token: 'xapp-...'"
            echo "       api_token: 'xoxb-...'"
            echo ""
            exit 1
        fi
    else
        echo "✗ Config file not found: $CONFIG_FILE"
        echo "Run 'crybot onboard' first"
        exit 1
    fi
else
    echo "✓ Slack tokens found in environment"
fi

# Check if crybot is built
if [ ! -f "./bin/crybot" ]; then
    echo "✗ Crybot not built. Building..."
    make build
fi

echo ""
echo "=== Starting Crybot with Slack ==="
echo ""
echo "Before starting, make sure you:"
echo "1. Have created a Slack app at https://api.slack.com/apps"
echo "2. Enabled Socket Mode and generated a token"
echo "3. Installed the app and copied the Bot User OAuth Token"
echo "4. Invited the bot to a test channel: /invite @YourBotName"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start crybot with only Slack feature enabled
if [ -z "$SLACK_SOCKET_TOKEN" ]; then
    # Tokens in config file
    exec ./bin/crybot
else
    # Tokens in environment - we need to ensure slack feature is enabled
    # Create a temp config with slack enabled
    TEMP_CONFIG=$(mktemp)
    cat "$HOME/.crybot/workspace/config.yml" > "$TEMP_CONFIG"

    # Ensure features section exists and has slack: true
    if grep -q "^features:" "$TEMP_CONFIG"; then
        if ! grep -q "^  slack:" "$TEMP_CONFIG"; then
            sed -i '/^features:/a\  slack: true' "$TEMP_CONFIG"
        else
            sed -i 's/^  slack:.*/  slack: true/' "$TEMP_CONFIG"
        fi
    else
        echo "features:" >> "$TEMP_CONFIG"
        echo "  slack: true" >> "$TEMP_CONFIG"
    fi

    echo "Testing with temporary config..."
    CRYBOT_CONFIG="$TEMP_CONFIG" exec ./bin/crybot
fi
