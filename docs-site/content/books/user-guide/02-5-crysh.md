Crysh is a natural language shell wrapper that generates shell commands from your descriptions using AI.

## What is Crysh?

Crysh (Crystal Shell) transforms natural language descriptions into shell commands. Instead of memorizing complex command syntax, just describe what you want to do:

```bash
# Instead of:
cut -d, -f2 file.csv

# Just say:
crysh get the second field separated by commas < file.csv
```

## Installation

Crysh is included with Crybot. After building, you'll have two binaries:

```bash
./bin/crybot  # Main AI assistant
./bin/crysh   # Shell wrapper
```

For system-wide installation:

```bash
sudo cp bin/crysh /usr/local/bin/
# or add to PATH:
export PATH="$PATH:$(pwd)/bin"
```

## Quick Start

### Initial Setup

Run the onboard wizard to configure API keys:

```bash
crysh onboard
```

The wizard will:
- Check for existing Crybot configuration
- Prompt for API keys (OpenRouter, Groq, OpenAI, etc.)
- Set up a fast, free model by default
- Create `~/.crybot/workspace/config.yml`

### Basic Usage

```bash
# Generate and execute with confirmation
crysh sort these lines by size

# Skip confirmation (useful in scripts)
crysh -y count unique lines

# Preview command without executing
crysh --dry-run extract the email addresses

# Verbose logging for debugging
crysh -v "complex transformation"
```

## Features

### Interactive Confirmation

By default, crysh shows a rofi dialog with three options:

- **Run** - Execute the generated command
- **Edit** - Modify the command before running
- **Cancel** - Abort the operation

The rofi interface keeps your stdin/stdout clean for data pipelines.

### Command Editing

When you select **Edit**, crysh opens your editor (`$EDITOR`):

```bash
export EDITOR="code -w"  # For VS Code
export EDITOR="vim"      # For Vim
export EDITOR="nano"     # For Nano
```

Or use rofi's inline editing mode if no editor is configured.

### Pipeline Integration

Crysh preserves stdin/stdout, making it perfect for pipelines:

```bash
# Count unique IPs from nginx logs
cat /var/log/nginx/access.log | crysh extract unique IP addresses | sort | uniq -c

# Process CSV data
cat data.csv | crysh "sort by column 3 numerically" > sorted.txt

# Chain multiple transformations
ls -l | crysh "get the size column" | crysh "calculate total size"
```

### Dry Run Mode

Preview commands before executing:

```bash
crysh --dry-run "find files larger than 100MB"
# Output: find . -type f -size +100M
```

### Verbose Mode

Debug what's happening under the hood:

```bash
crysh -v "parse json and extract name field"
```

## Examples

### Text Processing

```bash
# Extract specific fields
echo "a,b,c" | crysh get second field
# Output: b

# Sort and unique
cat log.txt | crysh sort by frequency and show duplicates
# Output: sort | uniq -c | sort -rn

# Pattern matching
curl -s https://example.com | crysh extract all email addresses
# Output: grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
```

### File Operations

```bash
# Find large files
crysh find files larger than 1 gigabyte
# Output: find . -type f -size +1G

# Clean up old files
crysh "find files older than 30 days and delete them"
# Output: find . -type f -mtime +30 -delete

# Rename files in bulk
crysh "rename all jpg files to lowercase"
# Output: find . -type f -name '*.JPG' -exec rename 'y/A-Z/a-z/' {} \;
```

### Data Analysis

```bash
# Calculate statistics
cat numbers.txt | crysh calculate the average
# Output: awk '{sum+=$1} END {print sum/NR}'

# Find extremes
cat data.csv | crysh find the row with the highest value
# Output: awk 'NR==1 || $3 > max {max=$3; line=$0} END {print line}'

# Filter and transform
ls -l | crysh "show only directories sorted by size"
# Output: grep '^d' | sort -k5 -n
```

## Configuration

Crysh uses Crybot's configuration file: `~/.crybot/workspace/config.yml`

### Recommended Models

For command generation, use fast models:

```yaml
agents:
  defaults:
    provider: openrouter
    model: stepfun/step-3.5-flash:free  # Free & fast

    # Or try:
    # provider: groq
    # model: llama-3.3-8b-it  # Very fast

    # provider: zhipu
    # model: glm-4.7-flash  # Free tier
```

### Provider Setup

```yaml
providers:
  openrouter:
    api_key: "sk-or-..."  # Get at openrouter.ai
  groq:
    api_key: "gsk_..."    # Get at console.groq.com
  openai:
    api_key: "sk-..."     # OpenAI API key
```

## Command Line Options

```
Usage: crysh [OPTIONS] <description>

Options:
  -y               Skip confirmation and execute immediately
  --dry-run        Show command without executing
  -v               Verbose logging for debugging
  -h, --help       Show help message
  onboard          Run setup wizard

Arguments:
  description      Natural language description of desired operation
```

## Tips and Tricks

### Shell Aliases

Create aliases for common operations:

```bash
alias csv2nd='crysh "convert csv to tab-separated"'
alias json2yaml='crysh "convert json to yaml"'
alias sort-size='crysh "sort by file size"'
```

### Script Integration

Use `-y` flag in scripts for automation:

```bash
#!/bin/bash
# Backup large files
find . -type f | crysh -y "find files larger than 100MB" | \
while read file; do
  cp "$file" /backup/
done
```

### Learning Commands

Use dry-run to learn new commands:

```bash
crysh --dry-run "monitor file changes in real time"
# Learn about: inotifywait -m .

crysh --dry-run "compare two directories"
# Learn about: diff -rq dir1/ dir2/
```

## Troubleshooting

### Command Errors

If a generated command fails:

1. Run with `-v` to see the command
2. Use `--dry-run` to inspect without executing
3. Select **Edit** in rofi to fix the command
4. Report issues with the LLM model output

### Slow Response

- Switch to a faster model (Groq, OpenRouter free tier)
- Check your internet connection
- Use `--dry-run` to test without API calls

### Rofi Not Available

If rofi isn't installed:

```bash
# Ubuntu/Debian
sudo apt install rofi

# Arch Linux
sudo pacman -S rofi

# macOS
brew install rofi
```

Or use `-y` flag to skip the confirmation dialog.

## Advanced Usage

### Combining with Shell Features

```bash
# Command substitution
cmd=$(crysh --dry-run "sort numerically")
eval "$cmd" < file.txt

# Process substitution
crysh "analyze data" < <(generate_data)

# Here documents
crysh "parse csv" << EOF
name,age,city
Alice,30,NYC
Bob,25,LA
EOF
```

### Error Handling

```bash
# Check if command succeeded
if output=$(crysh -y "extract data" 2>&1); then
  echo "$output"
else
  echo "Failed: $output" >&2
fi
```

## See Also

- [Configuration](02-configuration.md) - Full config reference
- [Built-in Tools](11-tools.md) - Tools available in Crybot
- [Free AI Models](13-free-models.md) - Recommended free models
