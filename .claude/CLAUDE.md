# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

macOS shell scripts that format GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copy it to the clipboard for pasting into Slack with clickable links and custom emoji.

## Architecture

Scripts live in `scripts/`:

**`gh-clippy.sh`** — formats GitHub PRs/issues as rich text for Slack:
1. Calls `gh` CLI to fetch JSON data
2. Uses `jq` to transform JSON into HTML (with `<a>` links) and plain text
3. Uses an inline Swift snippet (`swift -e`) with `AppKit`/`NSPasteboard` to copy both `public.html` and plain string types to the macOS clipboard — Slack preserves hyperlinks from the HTML pasteboard type

**`gh-syms.sh`** — creates branch-named symlinks for git repo directories:
1. Finds real directories in CWD matching a given prefix (e.g. `django`, `django2`, `django3`)
2. Reads each directory's current git branch
3. Removes old symlinks targeting those directories (matched by `readlink` target)
4. Creates symlinks of the form `<dirname>-<branch>` → `<dirname>`
5. Lists the current symlinks

Default run (no subcommand) does all three phases: remove → create → list.

## Running

### gh-clippy.sh

```bash
# Open, ready-for-review PRs authored by you
./scripts/gh-clippy.sh pr

# All PRs (merged, closed, draft, etc.)
./scripts/gh-clippy.sh pr --all

# Specific PRs by number
./scripts/gh-clippy.sh pr 12595 12593

# Open issues assigned to you
./scripts/gh-clippy.sh issue

# All issues (open + closed)
./scripts/gh-clippy.sh issue --all

# Specific issues by number
./scripts/gh-clippy.sh issue 42 57
```

### gh-syms.sh

```bash
# Remove stale symlinks, create fresh ones, list (default)
./scripts/gh-syms.sh django

# Same with verbose removal/creation output
./scripts/gh-syms.sh django --verbose

# List existing symlinks only
./scripts/gh-syms.sh django list

# Remove all symlinks for django* directories
./scripts/gh-syms.sh django clean

# Also process django-old, django_bak, etc. (default is strict: django, django2, django3 only)
./scripts/gh-syms.sh django --no-strict-nums-only
```

## Dependencies

- macOS (uses `NSPasteboard` via Swift) — required for `gh-clippy.sh` only
- `gh` CLI (authenticated) — required for `gh-clippy.sh` only
- `jq` — required for `gh-clippy.sh` only
- Swift runtime (ships with Xcode / Command Line Tools) — required for `gh-clippy.sh` only
- `git` — required for `gh-syms.sh`

## Conventions

- Scripts use `set -euo pipefail`
- PR state is mapped to custom Slack emoji (`:git--merged:`, `:git--approved:`, etc.) via jq
- Timestamps are converted from UTC to CST (UTC-6 hardcoded offset) and formatted as `Mon DD H:MMam/pm`

## Versioning

All scripts share the same repo release version. When updating the `VERSION` variable in any script, update it in **all** scripts at the same time:
- `scripts/gh-clippy.sh`
- `scripts/gh-syms.sh`

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
