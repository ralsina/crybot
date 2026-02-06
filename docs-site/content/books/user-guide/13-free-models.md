# Free AI Models

This chapter covers how to use Crybot with **free AI models** and providers that offer free tiers.

> **Note:** AI model pricing and free tier availability change frequently. The information below reflects the state of these services at the time of writing. Always verify current pricing and terms directly with each provider before relying on them for your use case.

## Quick Start: Free Options

| Provider | Model | Free Tier | How to Get |
|----------|-------|-----------|------------|
| **Zhipu GLM** | `glm-4-flash`, `glm-4-plus`, `glm-4-alltools` | Yes | [bigmodel.cn](https://open.bigmodel.cn/) |
| **Groq** | `llama-3.3-70b-versatile`, `llama-3.1-8b-instant` | Yes | [console.groq.com](https://console.groq.com/) |
| **OpenRouter** | `deepseek-chat`, `qwen-*` | Yes | [openrouter.ai](https://openrouter.ai/) |
| **Hugging Face** | Various | Yes | [huggingface.co](https://huggingface.co/) |
| **Local** | vLLM | Free | Run on your hardware |

---

## 1. Zhipu GLM (Recommended for Free Use)

Zhipu AI offers generous free tiers for their GLM models.

### Getting Started

1. Visit [https://open.bigmodel.cn/](https://open.bigmodel.cn/)
2. Sign up for a free account
3. Get your API key from the console
4. Add to Crybot config:

```yaml
providers:
  zhipu:
    api_key: "your_zhipu_api_key"

agents:
  defaults:
    provider: zhipu
    model: "glm-4-flash"  # Fast and free
    # model: "glm-4-plus"   # More capable
    # model: "glm-4-alltools" # With function calling
```

### Available Models

| Model | Description | Best For |
|-------|-------------|----------|
| `glm-4-flash` | Fast, efficient | Chat, quick responses |
| `glm-4-plus` | Capable all-rounder | Complex tasks |
| `glm-4-alltools` | With function calling | Tool use, agents |

### Free Tier Limits

- Daily token allowance
- Rate limits apply after quota exceeded
- Multiple models share the same free quota

---

## 2. Groq (Lightning Fast)

Groq offers free access to open-source models with incredibly fast inference.

### Getting Started

1. Visit [https://console.groq.com/](https://console.groq.com/)
2. Sign up for free
3. Get your API key from the dashboard
4. Add to Crybot config:

```yaml
providers:
  groq:
    api_key: "your_groq_api_key"
    tools: false  # Required for free tier (6000 TPM limit)

agents:
  defaults:
    provider: groq
    model: "llama-3.1-8b-instant"  # Smaller model for free tier
    # model: "llama-3.3-70b-versatile"
    # model: "qwen/qwen3-32b"
```

### Available Models

| Model | Parameters | Notes |
|-------|------------|-------|
| `llama-3.3-70b-versatile` | 70B | Fast, capable, production-ready |
| `llama-3.1-8b-instant` | 8B | Very fast, good for simple tasks |
| `qwen3-32b` | 32B | Strong instruction following |
| `gpt-oss-120b` | 120B | OpenAI's open-source model |

### Free Tier

- Free access to Groq-hosted models
- Rate limited but very fast
- No credit card required
- Check [Groq's docs](https://console.groq.com/docs/models) for current model list

> **Important Limitation:** Groq's free tier has a **6000 tokens-per-minute (TPM)** limit. Crybot's system prompt (skills, memory, instructions) is approximately 8000-9000 tokens, which exceeds this limit.
>
> **For Groq free tier to work:**
> - Set `tools: false` in the Groq provider config
> - The system will still be too large for the free tier
> - **Recommended:** Use Groq only if you upgrade to a paid tier, or use Zhipu GLM for free instead

### Paid Tier

Upgrading to Groq's Dev Tier or higher provides:
- Higher TPM limits (suitable for Crybot's full system prompt)
- Tool use support (set `tools: true`)
- Access to more models

---

## 3. OpenRouter (Access to Many Providers)

OpenRouter aggregates multiple AI providers, including free options.

### Getting Started

1. Visit [https://openrouter.ai/](https://openrouter.ai/)
2. Sign up and get API key
3. Configure Crybot:

```yaml
providers:
  openrouter:
    api_key: "your_openrouter_key"

agents:
  defaults:
    provider: openrouter
    model: "deepseek/deepseek-chat"
    # model: "qwen/qwen-2.5-72b-instruct"
```

### Free Models on OpenRouter

| Model | Provider | Notes |
|-------|----------|-------|
| `deepseek-chat` | DeepSeek | Very capable, currently free |
| `qwen-2.5-72b-instruct` | Alibaba | Strong instruction following |
| `meta-llama/llama-3-8b` | Meta | Open source, some free tier |

### Pricing

- Pay-per-use model
- Some providers have free tiers
- Check model page for current pricing

---

## 4. Hugging Face Inference API

Hugging Face offers free inference for many open-source models.

### Getting Started

1. Visit [https://huggingface.co/](https://huggingface.co/)
2. Sign up for free account
3. Get your API token
4. Add to Crybot as an OpenAI-compatible endpoint:

```yaml
providers:
  openai:
    api_key: "hf_your_token_here"
    base_url: "https://api-inference.huggingface.co/v1"
```

### Available Models

Use any Hugging Face model with "Inference" badge:

```yaml
model: "meta-llama/Meta-Llama-3-8B-Instruct"
model: "mistralai/Mistral-7B-Instruct-v0.3"
model: "Qwen/Qwen2.5-72B-Instruct"
```

### Free Tier

- Free inference for supported models
- Rate limits apply
- Good for testing and light usage

---

## 5. Local Models with vLLM (Completely Free)

Run models on your own hardware - completely free after setup.

### Requirements

- NVIDIA GPU with 8GB+ VRAM recommended
- Linux OS
- vLLM installation

### Getting Started

1. Install vLLM:

```bash
# Using Docker (recommended)
docker run --gpus all -v $PWD/models:/root/.cache/vllm \
  -p 8000:8000 \
  vllm/vllm-openai:latest \
  --model meta-llama/Meta-Llama-3-8B-Instruct

# Or install locally
pip install vllm
python -m vllm.model --model meta-llama/Meta-Llama-3-8B-Instruct
```

2. Configure Crybot:

```yaml
providers:
  vllm:
    api_base: "http://localhost:8000/v1"
    api_key: "any_key_here"  # Required but not used by vLLM

agents:
  defaults:
    model: "meta-llama/Meta-Llama-3-8B-Instruct"
```

### Model Options

| Model | VRAM | Notes |
|-------|------|-------|
| Llama-3-8B | 8GB | Good balance |
| Llama-3-70B | 40GB | More capable |
| Mistral-7B | 8GB | Fast |
| Qwen2-7B | 8GB | Strong |

### Download Models First

```bash
# Using huggingface-cli
pip install huggingface_hub
huggingface-cli download meta-llama/Meta-Llama-3-8B-Instruct
```

---

## Comparison: Free Options

| Provider | Setup Difficulty | Speed | Quality | Cost |
|----------|-----------------|-------|----------|------|
| **Zhipu** | Easy | Fast | Excellent | Free tier |
| **Groq** | Easy | Very Fast | Good | Free tier |
| **OpenRouter** | Easy | Fast | Varies | Pay-per-use |
| **Hugging Face** | Easy | Medium | Good | Free tier |
| **vLLM** | Complex | Fastest | Varies | Free (hardware) |

---

## Recommended Configuration for Free Use

### Option 1: Zhipu GLM (Easiest)

```yaml
providers:
  zhipu:
    api_key: "your_zhipu_api_key"

agents:
  defaults:
    provider: zhipu
    model: "glm-4-flash"
    temperature: 0.7
```

### Option 2: Groq (Fastest - Paid Tier Recommended)

> **Warning:** Groq's free tier (6000 TPM) is **too limited for Crybot**. The system prompt alone exceeds this limit.
>
> **Groq is only recommended if:**
> - You upgrade to Dev Tier or higher ($0.59/million tokens)
> - You want the fastest inference and don't mind paying

```yaml
providers:
  groq:
    api_key: "your_groq_api_key"
    tools: true  # Enable tools with paid tier

agents:
  defaults:
    provider: groq
    model: "llama-3.3-70b-versatile"
```

### Option 3: Local vLLM (No API needed)

```yaml
providers:
  vllm:
    api_base: "http://localhost:8000/v1"
    api_key: "unused"

agents:
  defaults:
    provider: vllm
    model: "meta-llama/Meta-Llama-3-8B-Instruct"
```

---

## Next Steps

1. **Choose a provider** from the options above
2. **Get an API key** (if required)
3. **Update your config**: `~/.crybot/config.yml`
4. **Test**: `./bin/crybot agent "Hello, can you help me?"`

For configuration details, see [Configuration](./02-configuration.md).
