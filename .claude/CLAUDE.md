# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS shell scripts that format GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copy it to the clipboard for pasting into Slack with clickable links and custom emoji.

## Architecture

Scripts live in `scripts/`:

**`gh-to-slack-pasteboard.sh`** — formats GitHub PRs/issues as rich text for Slack:
1. Calls `gh` CLI to fetch JSON data
2. Uses `jq` to transform JSON into HTML (with `<a>` links) and plain text
3. Uses an inline Swift snippet (`swift -e`) with `AppKit`/`NSPasteboard` to copy both `public.html` and plain string types to the macOS clipboard — Slack preserves hyperlinks from the HTML pasteboard type

**`gh-create-syms.sh`** — creates branch-named symlinks for git repo directories:
1. Finds real directories in CWD matching a given prefix (e.g. `django`, `django2`, `django3`)
2. Reads each directory's current git branch
3. Removes old symlinks targeting those directories (matched by `readlink` target)
4. Creates symlinks of the form `<dirname>-<branch>` → `<dirname>`

## Running

### gh-to-slack-pasteboard.sh

```bash
# Open, ready-for-review PRs authored by you
./scripts/gh-to-slack-pasteboard.sh pr

# All PRs (merged, closed, draft, etc.)
./scripts/gh-to-slack-pasteboard.sh pr --all

# Specific PRs by number
./scripts/gh-to-slack-pasteboard.sh pr 12595 12593

# Open issues assigned to you
./scripts/gh-to-slack-pasteboard.sh issue

# All issues (open + closed)
./scripts/gh-to-slack-pasteboard.sh issue --all

# Specific issues by number
./scripts/gh-to-slack-pasteboard.sh issue 42 57
```

### gh-create-syms.sh

```bash
# Create/refresh symlinks for all django* directories
./scripts/gh-create-syms.sh django

# List existing symlinks
./scripts/gh-create-syms.sh django list

# Remove all symlinks for django* directories
./scripts/gh-create-syms.sh django clean

# Only operate on django, django2, django3, … (skip django-old, etc.)
./scripts/gh-create-syms.sh django --strict

# Subcommands and --strict compose freely
./scripts/gh-create-syms.sh django list --strict
./scripts/gh-create-syms.sh django clean --strict
```

## Dependencies

- macOS (uses `NSPasteboard` via Swift) — required for `gh-to-slack-pasteboard.sh` only
- `gh` CLI (authenticated) — required for `gh-to-slack-pasteboard.sh` only
- `jq` — required for `gh-to-slack-pasteboard.sh` only
- Swift runtime (ships with Xcode / Command Line Tools) — required for `gh-to-slack-pasteboard.sh` only
- `git` — required for `gh-create-syms.sh`

## Conventions

- Scripts use `set -euo pipefail`
- PR state is mapped to custom Slack emoji (`:git--merged:`, `:git--approved:`, etc.) via jq
- Timestamps are converted from UTC to CST (UTC-6 hardcoded offset) and formatted as `Mon DD H:MMam/pm`

## Versioning

All scripts share the same repo release version. When updating the `VERSION` variable in any script, update it in **all** scripts at the same time:
- `scripts/gh-to-slack-pasteboard.sh`
- `scripts/gh-create-syms.sh`

## GitHub CLI

When viewing GitHub issues, always use `--json` format to avoid GraphQL deprecation warnings:
```bash
gh issue view <number> --json title,body,labels,state,comments
```
Never use bare `gh issue view <number>` without `--json`.

## Allowed Bash Permissions

The following GitHub CLI read operations are pre-approved:
- `gh issue view` / `gh issue list` — read issue data
- `gh pr view` / `gh pr list` — read PR data
- `mkdir -p` — create directories
- `$()` — command substitution, when the command contains `$(cat <<EOF` (used for multi-line strings in git commits, gh CLI, etc.)
