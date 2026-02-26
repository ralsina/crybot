This chapter covers installing Crybot on your system.

## Quick Install (Recommended)

The easiest way to install Crybot is using the installation script, which downloads the latest pre-built binary for your system:

```bash
curl -sSL https://crybot.ralsina.me/install.sh | bash
```

This will:

- ✅ Detect your system architecture (linux-amd64, linux-arm64, etc.)
- ✅ Download the latest binary from GitHub releases
- ✅ Install it to `~/.local/bin`
- ✅ Run the onboarding wizard
- ✅ Optionally create a systemd service for auto-start

### Manual Download

You can also download the binary manually from the [releases page](https://github.com/ralsina/crybot/releases):

1. Download the binary for your platform (linux-amd64, linux-arm64, etc.)
2. Make it executable: `chmod +x crybot`
3. Move it to your PATH: `mv crybot ~/.local/bin/`

### Install Options

For more control over the installation, download the script first:

```bash
# Download install script
curl -O https://crybot.ralsina.me/install.sh
chmod +x install.sh
```

Then run with options:

```bash
# Show help
./install.sh --help

# Install specific version
./install.sh --version v0.1.1

# Skip onboarding (configure manually later)
./install.sh --skip-onboarding

# Create systemd service (starts when you log in)
./install.sh --service user

# Create auto-start service (runs 24/7)
./install.sh --service auto
```

## Systemd Service

Crybot can run as a systemd user service, starting automatically when you log in or running 24/7.

### Start on Login

To start Crybot when you log into your system:

```bash
./install.sh --service user
```

Then enable the service:

```bash
systemctl --user daemon-reload
systemctl --user enable crybot.service
systemctl --user start crybot.service
```

### Run 24/7 (Auto-Start)

To run Crybot continuously (even when you're logged out):

```bash
./install.sh --service auto
```

Then enable lingering:

```bash
systemctl --user daemon-reload
systemctl --user enable crybot.service
systemctl --user start crybot.service
loginctl enable-linger $USER
```

### Service Management

```bash
# Check status
systemctl --user status crybot.service

# View logs
journalctl --user -u crybot.service -f

# Restart service
systemctl --user restart crybot.service

# Stop service
systemctl --user stop crybot.service
```

## Updating

Update Crybot to the latest version:

```bash
curl -sSL https://crybot.ralsina.me/update.sh | bash
```

Or download the script first for more options:

```bash
# Download update script
curl -O https://crybot.ralsina.me/update.sh
chmod +x update.sh

# Update latest version
./update.sh

# Update and restart service
./update.sh --restart-service

# Update to specific version
./update.sh --version v0.1.1
```

## Uninstalling

Remove Crybot from your system:

```bash
# Download uninstall script
curl -O https://crybot.ralsina.me/uninstall.sh
chmod +x uninstall.sh

# Remove Crybot (keep config)
./uninstall.sh

# Remove configuration too
./uninstall.sh --purge

# Stop service before uninstalling
./uninstall.sh --stop-service
```

## Build from Source

If you prefer to build from source or want to contribute:

### Prerequisites

Crybot requires:

- **Crystal** 1.13.0 or later
- **shards** - Crystal dependency manager (comes with Crystal)

#### Installing Crystal

**Arch Linux:**
```bash
pacman -S crystal shards
```

**Ubuntu/Debian:**
```bash
# See https://crystal-lang.org/install/ for instructions
```

**From source:** See [crystal-lang.org](https://crystal-lang.org/install/)

### Build Steps

1. Clone the repository:
```bash
git clone https://github.com/ralsina/crybot.git
cd crybot
```

2. Install dependencies:
```bash
shards install
```

3. Build Crybot:
```bash
make build
```

Or manually:
```bash
crystal build src/main.cr -o bin/crybot -Dpreview_mt -Dexecution_context
```

**Important:** Crybot requires `-Dpreview_mt -Dexecution_context` flags for multi-threading and isolated fiber support. These flags are **NOT supported by `shards build`**, so use `make build` instead.

### Installing from Build

After building, you can install it:

```bash
make install
# Or manually:
cp bin/crybot ~/.local/bin/
```

## Verifying Installation

Test that Crybot works:

```bash
crybot agent "Hello, Crybot!"
```

You should see a response from the AI assistant.

## Workspace Structure

Crybot creates its workspace in `~/.crybot/`:

```
~/.crybot/
├── config.yml              # Main configuration
├── workspace/
│   ├── MEMORY.md           # Long-term memory
│   ├── skills/             # AI skills
│   ├── memory/             # Daily logs
│   └── scheduled_tasks.yml # Scheduled tasks
├── sessions/               # Chat history
├── logs/                   # Application logs
├── monitor/                # Landlock sandbox permissions
└── repl_history.txt        # REPL command history
```

## Next Steps

Once installed, you need to configure Crybot with your API keys. Continue to [Configuration](02-configuration.md).

> **Looking for free AI models?** Crybot supports several free-tier providers including Zhipu GLM, Groq, and more. See [Free AI Models](13-free-models.md) for options that don't require a paid subscription.
