# LLM Status

A lightweight macOS menu bar app that monitors the operational status of major LLM providers in real time. One glance at the menu bar tells you whether the model you depend on is healthy — or whether the bug you're chasing is on their side.

![LLM Status popover](docs/screenshot.png)

## Supported providers

Anthropic (Claude), OpenAI, Cursor, Google (Gemini), Mistral AI, DeepSeek, Moonshot AI, OpenRouter, Perplexity, xAI (Grok), Groq.

## Features

- **Menu bar indicator** — cloud icon tinted by aggregated severity (green / yellow / orange / red).
- **Component drill-down** — expand any provider to see per-component status (e.g. Claude API vs Claude Code, OpenAI Chat Completions vs Sora).
- **Active incident surfacing** — incidents in `investigating` / `identified` / `monitoring` phases are shown inline, even when the provider's global indicator is still green.
- **Watched component** — pin a single component per provider so the menu bar reflects only what you care about.
- **Notifications** — opt-in alerts for incident start and recovery, scoped to one provider or all.
- **Disable / reorder** providers via Settings.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (only for building from source)

## Install

Grab the latest `LLMStatus.app` from the [Releases](https://github.com/jean-philippe-lefebvre/llmStatus/releases) page, or build it yourself:

```bash
make run        # build + sign + install to /Applications + launch
make install    # build + sign + install to /Applications
make all        # build the .app bundle into .build/app/
```

## How status is fetched

| Source | Providers |
|---|---|
| Atlassian Statuspage API | Anthropic, OpenAI, Cursor, DeepSeek, Moonshot |
| incident.io API | Groq |
| Google Cloud incidents JSON | Gemini |
| HTML scraping | Mistral, OpenRouter, Perplexity |
| Headless WebKit (Cloudflare bypass) | xAI |

All HTTP calls go through a shared `URLSession` with short timeouts; xAI uses a hidden `WKWebView` and caches the result for 10 minutes.

## Development

See [`CLAUDE.md`](CLAUDE.md) for architecture notes, key patterns, and the build/packaging pipeline.

```bash
swift build      # debug build
swift test       # tests
make clean       # wipe build/ and SPM cache
```

## License

MIT
