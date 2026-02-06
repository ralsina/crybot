# Free AI Models

This chapter covers how to use Crybot with **free AI models** and providers that offer free tiers.

> **⭐ Recommended: OpenRouter**
> OpenRouter provides access to many free models from various providers, including the excellent Arcee Trinity. No credit card required, generous free tiers, and multiple models to choose from. Get your API key from [openrouter.ai](https://openrouter.ai/).

> **Note:** AI model pricing and free tier availability change frequently. The information below reflects the state of these services at the time of writing. Always verify current pricing and terms directly with each provider before relying on them for your use case.

## Quick Start: Free Options

| Provider | Models | Free Tier | Speed | Tool Support | Free Amount | How to Get |
|----------|--------|-----------|-------|--------------|-------------|------------|
| **OpenRouter** ⭐ | Step-3.5, GLM, DeepSeek, Qwen, Llama | Yes | Very Fast | ✅ Excellent | Multiple free options | [openrouter.ai](https://openrouter.ai/) |
| **Zhipu GLM** | `glm-4-flash`, `glm-4-plus` | Generous | Fast | ✅ Excellent | High daily limit | [bigmodel.cn](https://open.bigmodel.cn/) |
| **Groq** | `llama-3.3-70b-versatile` | Yes | Very Fast | ⚠️ Limited* | 12K TPM | [console.groq.com](https://console.groq.com/) |
| **Google Gemini** | `gemini-2.5-flash` | **100% FREE** | Very Fast | ✅ Excellent | 20 req/day† | [ai.google.dev](https://ai.google.dev/gemini-api/docs) |
| **Hugging Face** | Various | Yes | Medium | ✅ Good | Rate limits | [huggingface.co](https://huggingface.co/) |
| **Local** | vLLM | Free | Fastest | ✅ Good | None | Run on your hardware |

*Groq's `llama-3.3-70b-versatile` has 12K TPM but generates malformed tool calls. Use `qwen/qwen3-32b` with `lite: true` for working tools (6K TPM).
†Gemini free tier has a very low daily request limit (20/day). Better for occasional use.

---

## 1. OpenRouter ⭐ (Many Free Models)

OpenRouter aggregates multiple AI providers and offers several free models, making it an excellent choice for accessing cutting-edge AI without cost.

### Why OpenRouter?

- **Multiple Free Models**: Access to many free models from different providers
- **Step-3.5 Flash**: Very fast, excellent tool support - ⭐ **Top recommendation**
- **Variety**: Choose from different models based on your needs
- **Easy Setup**: Single API key works with all models
- **No Credit Card Required**: Start using free models immediately
- **Tool Support**: Most free models support function calling for Crybot tools

### Getting Started

1. Visit [https://openrouter.ai/](https://openrouter.ai/)
2. Sign up for a free account
3. Get your API key from the dashboard
4. Add to Crybot config:

```yaml
providers:
  openrouter:
    api_key: "your_openrouter_key"
    # lite: false  # Most free models support tools; set to true only if using models without tool support

agents:
  defaults:
    provider: openrouter
    model: "stepfun/step-3.5-flash:free"  # ⭐ Recommended - Very fast, excellent tools!
    # model: "z-ai/glm-4.5-air:free"  # Alternative - Fast, excellent tool support
    # model: "tngtech/deepseek-r1t2-chimera:free"  # Alternative (slower)
    # model: "arcee-ai/trinity-large-preview:free"  # Fast but NO tool support via OpenRouter
```

### Available Free Models

| Model | Provider | Description | Tool Support |
|-------|----------|-------------|--------------|
| `stepfun/step-3.5-flash:free` | StepFun | ⭐ **Recommended** - Very fast, excellent tool support | ✅ Yes |
| `z-ai/glm-4.5-air:free` | Zhipu AI | Fast, high quality, excellent tool support | ✅ Yes |
| `tngtech/deepseek-r1t2-chimera:free` | DeepSeek | Free DeepSeek model, good for reasoning | ✅ Yes |
| `qwen/qwen-2.5-72b-instruct` | Alibaba | Strong instruction following, capable model | ✅ Yes |
| `arcee-ai/trinity-large-preview:free` | Arcee AI | Fast, high quality for chat | ⚠️ **No tool support via OpenRouter** |
| `meta-llama/llama-3.3-70b-instruct:free` | Meta | Capable model, often rate-limited | ✅ Yes |
| `google/gemma-7b-it:free` | Google | Gemma model, lightweight and efficient | ⚠️ Limited |

> **Note:** The `:free` suffix indicates a free tier model. Always check the OpenRouter website for the latest availability of free models.

### Tool Support

Most free models on OpenRouter support function calling, which means all Crybot tools (file operations, shell commands, web search, memory, etc.) will work properly. **Top recommendations for tool support:** `stepfun/step-3.5-flash:free` (very fast), `z-ai/glm-4.5-air:free` (reliable), and `tngtech/deepseek-r1t2-chimera:free` (good reasoning). Note that **Arcee Trinity does not support tool calling via OpenRouter** - it outputs code blocks instead of calling tools.

### Free Tier Details

- Multiple models with free tiers available
- Rate limits vary by model
- No credit card required for free models
- Can switch between models easily in config

---

## 2. Zhipu GLM (Reliable Free Tier)

Zhipu AI offers generous free tiers with good daily limits for their GLM models.

### Why Zhipu GLM?

- **Generous Free Tier**: High daily limits suitable for regular use
- **Fast**: Optimized for quick responses
- **Excellent Tool Support**: Full function calling support for all Crybot tools
- **Multiple Models**: Flash for speed, Plus for capability, AllTools for agents
- **Easy Setup**: Simple API key from bigmodel.cn

### Free Tier Limits

- Daily token allowance with generous limits
- Multiple models share the same free quota
- Rate limits apply after quota exceeded
- Much higher daily limits than Gemini's 20 requests/day

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

### Free Tier

- Generous daily token allowance
- No credit card required
- Full tool calling support
- High daily limits suitable for regular use

---

## 3. Google Gemini (Free but Limited - 20 req/day)

Google Gemini 2.5 Flash is **completely free** with excellent speed and full tool calling support, but has a very low daily request limit.

### Why Consider Gemini?

- **100% Free**: No input/output charges, no hidden costs
- **Very Fast**: Optimized for quick responses
- **Excellent Tool Support**: Full function calling support for all Crybot tools
- **Easy Setup**: Simple API key from ai.google.dev

### Free Tier Limits

- **20 requests per day** for `gemini-2.5-flash` on free tier
- After hitting the limit, you must wait ~24 hours or upgrade to a paid plan
- For heavier usage, consider OpenRouter or Zhipu GLM instead

> **Note:** Gemini's free tier has a strict daily request limit (20/day). If you need more requests, use OpenRouter or Zhipu GLM which have higher limits.

### Getting Started

1. Visit [https://ai.google.dev/gemini-api/docs](https://ai.google.dev/gemini-api/docs)
2. Sign up for a free account (Google account required)
3. Get your API key from the console
4. Add to Crybot config:

```yaml
providers:
  gemini:
    api_key: "your_gemini_api_key"

agents:
  defaults:
    provider: gemini
    model: "gemini-2.5-flash"  # Fast and free
    # model: "gemini-2.5-pro"   # More capable, also free
```

### Available Models

| Model | Description | Best For |
|-------|-------------|----------|
| `gemini-2.5-flash` | Fast, efficient | Chat, quick responses, tool use |
| `gemini-2.5-pro` | More capable | Complex tasks, reasoning |

### Free Tier

- Completely free with no per-token charges
- **20 requests per day limit** (very restrictive)
- No credit card required
- Full tool calling support

---

## 4. Groq (Lightning Fast)

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
- **Recommended:** Use OpenRouter or Zhipu GLM for free instead - more reliable tool use

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

## 5. Hugging Face Inference API

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

## 6. Local Models with vLLM (Completely Free)

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

| Provider | Setup Difficulty | Speed | Quality | Cost | Daily Limit | Tool Support |
|----------|-----------------|-------|----------|------|-------------|--------------|
| **OpenRouter** ⭐ | Easy | Very Fast | Excellent | Free tiers | Multiple free models | ✅ Excellent |
| **Zhipu** | Easy | Fast | Excellent | Free tier | High | ✅ Excellent |
| **Gemini** | Easy | Very Fast | Excellent | **100% Free** | 20 req/day | ✅ Excellent |
| **Groq** | Easy | Very Fast | Good | Free tier | 12K TPM | ⚠️ Limited* |
| **Hugging Face** | Easy | Medium | Good | Free tier | Rate limits | ✅ Good |
| **vLLM** | Complex | Fastest | Varies | Free (hardware) | None | ✅ Good |

*Groq's `llama-3.3-70b-versatile` has 12K TPM but generates malformed tool calls. Use `qwen/qwen3-32b` with `lite: true` for working tools (6K TPM).

> **Note on Arcee Trinity**: While fast and high quality, `arcee-ai/trinity-large-preview:free` does NOT support tool calling via OpenRouter. For tool use, stick with `stepfun/step-3.5-flash:free` or `z-ai/glm-4.5-air:free`.

*Groq's `llama-3.3-70b-versatile` has 12K TPM but generates malformed tool calls. Use `qwen/qwen3-32b` with `lite: true` for working tools (6K TPM).

> **Note on Arcee Trinity**: While `arcee-ai/trinity-large-preview:free` is fast and high quality for chat, it does NOT support tool calling via OpenRouter - it outputs code blocks instead of calling tools. Use `z-ai/glm-4.5-air:free` for tool use.

*Groq's `llama-3.3-70b-versatile` has 12K TPM but generates malformed tool calls. Use `qwen/qwen3-32b` with `lite: true` for working tools (6K TPM).

---

## Recommended Configuration for Free Use

### Option 1: OpenRouter with Step-3.5 Flash ⭐ (Recommended)

```yaml
providers:
  openrouter:
    api_key: "your_openrouter_key"

agents:
  defaults:
    provider: openrouter
    model: "stepfun/step-3.5-flash:free"
    temperature: 0.7
```

### Option 2: OpenRouter with Zhipu GLM (Reliable Alternative)

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

### Option 3: Gemini (For Light Usage - 20 req/day)

```yaml
providers:
  gemini:
    api_key: "your_gemini_api_key"

agents:
  defaults:
    provider: gemini
    model: "gemini-2.5-flash"
```

### Option 4: Groq (Fastest - Full Functionality)

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

### Option 5: Local vLLM (No API needed)

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
