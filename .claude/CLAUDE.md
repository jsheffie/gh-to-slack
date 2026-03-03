# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS shell scripts that format GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copy it to the clipboard for pasting into Slack with clickable links and custom emoji.

## Architecture

Scripts live in `scripts/`. Each script is a self-contained Bash script that:
1. Calls `gh` CLI to fetch JSON data
2. Uses `jq` to transform JSON into HTML (with `<a>` links) and plain text
3. Uses an inline Swift snippet (`swift -e`) with `AppKit`/`NSPasteboard` to copy both `public.html` and plain string types to the macOS clipboard — Slack preserves hyperlinks from the HTML pasteboard type

## Running

```bash
# Default: open, ready-for-review PRs authored by you
./scripts/gh-pr-to-slack.sh

# All PRs (merged, closed, draft, etc.)
./scripts/gh-pr-to-slack.sh --all

# Specific PRs by number
./scripts/gh-pr-to-slack.sh 12595 12593
```

## Dependencies

- macOS (uses `NSPasteboard` via Swift)
- `gh` CLI (authenticated)
- `jq`
- Swift runtime (ships with Xcode / Command Line Tools)

## Conventions

- Scripts use `set -euo pipefail`
- PR state is mapped to custom Slack emoji (`:git--merged:`, `:git--approved:`, etc.) via jq
- Timestamps are converted from UTC to CST (UTC-6 hardcoded offset) and formatted as `Mon DD H:MMam/pm`
