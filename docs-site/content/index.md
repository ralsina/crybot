---
title: "Crybot"
---

<div class="hero">
  <div class="hero-content">
    <p class="tagline">Your Modular AI Assistant</p>
    <p class="hero-description">A fast, self-hosted AI assistant built in Crystal. Chat via web, Telegram, or voice. Extend with skills, MCP servers, and scheduled tasks.</p>
    <div class="hero-actions">
      <a href="/books/user-guide/01-installation.html" class="btn btn-primary">Get Started</a>
      <a href="https://github.com/ralsina/crybot" class="btn btn-secondary">View Source</a>
    </div>
  </div>
</div>

## What Makes Crybot Different?

<div class="feature-grid">

<div class="feature-card">
  <div class="feature-icon">💬</div>
  <h3>Multi-Interface</h3>
  <p>Chat through web UI, Telegram, voice commands, or a powerful REPL. Switch seamlessly between interfaces while maintaining context.</p>
</div>

<div class="feature-card">
  <div class="feature-icon">🧩</div>
  <h3>Skills System</h3>
  <p>Create reusable AI behaviors as simple markdown files. Build complex workflows without writing code.</p>
</div>

<div class="feature-card">
  <div class="feature-icon">🔌</div>
  <h3>MCP Integration</h3>
  <p>Connect to the growing ecosystem of Model Context Protocol servers for browser automation, filesystem access, and more.</p>
</div>

<div class="feature-card">
  <div class="feature-icon">⏰</div>
  <h3>Scheduled Tasks</h3>
  <p>Automate recurring AI tasks with natural language scheduling. Get daily summaries, news digests, or custom reports.</p>
</div>

<div class="feature-card">
  <div class="feature-icon">🚀</div>
  <h3>Blazing Fast</h3>
  <p>Built in Crystal for performance. Starts instantly, uses minimal resources, and handles concurrent operations efficiently.</p>
</div>

<div class="feature-card">
  <div class="feature-icon">🏠</div>
  <h3>Self-Hosted</h3>
  <p>Run it on your own hardware. Works with local models via vLLM or cloud providers of your choice. You're in control.</p>
</div>

</div>

## Quick Start

```bash
git clone https://github.com/ralsina/crybot.git
cd crybot
shards install
shards build
./bin/crybot onboard
./bin/crybot start
```

## Multiple AI Providers

Crybot works with the best AI models:

- **OpenAI** - GPT-4, GPT-4o, and more
- **Anthropic** - Claude 3.5 Sonnet, Opus
- **Zhipu GLM** - Free tier available
- **OpenRouter** - Access to 100+ models
- **vLLM** - Run local models

Provider is auto-detected from model name—no configuration needed.

## Ready to Dive In?

- **[User Guide](/books/user-guide/)** - Complete documentation
- **[Installation](/books/user-guide/01-installation.html)** - Get up and running
- **[GitHub Repository](https://github.com/ralsina/crybot)** - Star us!
