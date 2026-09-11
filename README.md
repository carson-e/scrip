# Scrip

A macOS menu-bar extra that shows Grok, Claude, and Cursor usage. There is no official quota API. Scrip keeps a **separate WebKit session per provider**, you sign in once, and it scrapes the usage page.

macOS 14+, Apple silicon. Menu-bar only — no Dock icon.

## Build

```sh
swift run ScripCoreCheck
./build.sh
open Scrip.app
```

Right-click Open the first time if Gatekeeper blocks the unsigned build.

## How it works

1. Sign in through the embedded browser for each provider.
2. Cookies stay on this Mac in an isolated WebKit data store (not shared across Grok / Claude / Cursor).
3. Every minute Scrip remounts each Usage tab and updates the menu bar.

This is unofficial. Site layout changes will break extraction. It may also conflict with those products’ terms of use.

## Why scrape

Shared bits (WebKit session, open Usage, read the DOM) can be generic. URLs, login walls, in-page tabs vs real pages, and parsers (“Weekly SuperGrok” vs “5-hour” vs “Included”) are per-site, so each provider is hardcoded.

None of these products expose a **consumer quota API** for what Scrip shows:

- **Grok** — SuperGrok weekly % is web-only.
- **Claude** — Anthropic’s Usage/Cost Admin APIs are Console/API token billing (org admin keys). Not claude.ai 5-hour / weekly limits.
- **Cursor** — Teams Admin API has spend/usage events (team API key). Not personal Included/API bars. Individuals still use the dashboard.

Until a provider ships that, scraping is the path.

## Privacy

Sessions never leave this computer. Sign out wipes that provider’s WebKit store. Cached percents live in UserDefaults under `scrip.snapshot.*`.
