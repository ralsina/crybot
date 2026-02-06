# Free AI Models

This chapter covers how to use Crybot with **free AI models** and providers that offer free tiers.

> **Note:** AI model pricing and free tier availability change frequently. The information below reflects the state of these services at the time of writing. Always verify current pricing and terms directly with each provider before relying on them for your use case.

## Quick Start: Free Options

| Provider | Model | Free Tier | How to Get |
|----------|-------|-----------|------------|
| **Zhipu GLM** | `glm-4-flash`, `glm-4-plus`, `glm-4-alltools` | Yes | [bigmodel.cn](https://open.bigmodel.cn/) |
| **Groq** | `llama-3.3-70b-versatile` (12K TPM) | Yes | [console.groq.com](https://console.groq.com/) |
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
    lite: false  # Full mode for models with sufficient TPM

agents:
  defaults:
    provider: groq
    model: "llama-3.3-70b-versatile"  # 12K TPM, but tools may be unstable
    # For working tools with Groq, consider:
    # model: "qwen/qwen3-32b"  # 6K TPM - working tools, requires lite mode
```

### Available Models

| Model | TPM (Free) | TPD (Free) | Notes |
|-------|------------|------------|-------|
| `llama-3.3-70b-versatile` | **12K** | 100K | **Recommended** - Fast, capable, 12K TPM enough for Crybot |
| `llama-3.1-8b-instant` | 6K | 500K | Very fast, requires `lite: true` |
| `qwen/qwen3-32b` | 6K | 500K | Strong instruction following, requires `lite: true` |
| `meta-llama/llama-guard-4-12b` | **15K** | 500K | Highest TPM, but specialized for safety |
| `gpt-oss-120b` | 8K | 200K | OpenAI's open-source model |

See [Groq Rate Limits](https://console.groq.com/docs/rate-limits) for current limits.

### Free Tier

- Free access to Groq-hosted models
- Rate limits vary by model (see table above)
- No credit card required
- **Recommended:** Use Zhipu GLM for free instead - more reliable tool use

> **Tool Use Limitations:**
> - `llama-3.3-70b-versatile`: Has 12K TPM but generates malformed tool calls
> - `qwen/qwen3-32b`: Working tools, but only 6K TPM (requires `lite: true`)
> - For reliable tool use on Groq free tier, consider `qwen/qwen3-32b` with `lite: true`

> **For models with 6K TPM** (llama-3.1-8b-instant, qwen/qwen3-32b):
> - Set `lite: true` to fit within the limit
> - Lite mode disables tools, skills, bootstrap files, and memory
> - You can have short conversations; long sessions will exceed the limit
> - Clear your session periodically: `rm ~/.crybot/sessions/YOUR_SESSION.jsonl`

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

### Option 2: Groq (Fastest - Full Functionality)

> **Recommended:** `llama-3.3-70b-versatile` has 12K TPM - supports full Crybot with `lite: false`

```yaml
providers:
  groq:
    api_key: "your_groq_api_key"
    lite: false  # Full mode with llama-3.3-70b-versatile (12K TPM)

agents:
  defaults:
    provider: groq
    model: "llama-3.3-70b-versatile"
```

> **Alternative for 6K TPM models:** Use `llama-3.1-8b-instant` with `lite: true` (limited features)

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
