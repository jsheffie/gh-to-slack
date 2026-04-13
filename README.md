# gh-to-slack

macOS shell scripts that format GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copy it to the clipboard for pasting into Slack with clickable links and custom emoji.

## Scripts

- **`gh-clippy`** — formats GitHub PRs/issues as rich text for Slack
- **`gh-syms`** — creates branch-named symlinks for git repo directories

## Install

### Homebrew (recommended)

```bash
brew install jsheffie/tap/gh-to-slack
```

### Manual

1. Create `~/bin` if it doesn't exist:

   ```bash
   mkdir -p ~/bin
   ```

2. Download the scripts and make executable:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/jsheffie/gh-to-slack/v1.0.7/scripts/gh-clippy.sh \
     -o ~/bin/gh-clippy && chmod +x ~/bin/gh-clippy

   curl -fsSL https://raw.githubusercontent.com/jsheffie/gh-to-slack/v1.0.7/scripts/gh-syms.sh \
     -o ~/bin/gh-syms && chmod +x ~/bin/gh-syms
   ```

3. Add `~/bin` to your PATH (if not already there):

   **zsh** (`~/.zshrc`):
   ```bash
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
   ```

   **bash** (`~/.bashrc`):
   ```bash
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
   ```

## Dependencies

- macOS (uses `NSPasteboard` via Swift for clipboard access) — `gh-clippy` only
- [`gh`](https://cli.github.com/) CLI (authenticated) — `gh-clippy` only
- [`jq`](https://jqlang.github.io/jq/) — `gh-clippy` only
- Swift runtime (ships with Xcode / Command Line Tools) — `gh-clippy` only
- `git` — `gh-syms` only

## Usage

### gh-clippy

List your recent PRs or issues formatted for Slack. Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

**Individual Developer Focused:**
Defaults to `@me` for status reporting.
```bash
gh-clippy pr                    # Open, ready-for-review PRs
gh-clippy pr --all              # All PRs
gh-clippy pr 12595 12593        # Specific PRs
gh-clippy pr --limit 20         # Up to 20 PRs
gh-clippy issue                 # Open issues assigned to me
gh-clippy issue --all           # All issues
gh-clippy issue 42 57           # Specific issues
gh-clippy issue --limit 5       # Show 5 issues
```

**Team/Management Focused:**

```bash
gh-clippy activity                    # Recent issues & PRs (defaults to 10 each)
gh-clippy activity --user-display     # With linked usernames
gh-clippy activity --limit 5          # 5 items per section
gh-clippy pr --user octocat           # Open PRs by octocat
gh-clippy issue --user bob --user ben # Issues for multiple users
gh-clippy users                       # List collaborators with links
```

### gh-syms

Create branch-named symlinks for git directories in the current working directory. Running without a subcommand removes stale symlinks, creates fresh ones, then lists the result.

By default only directories named exactly `<prefix>` or `<prefix><N>` (e.g. `django`, `django2`, `django3`) are processed — not `django-old` or `django_bak`.

```bash
gh-syms django                        # Remove stale, create fresh, list
gh-syms django --verbose              # Same, with removal/creation details
gh-syms django list                   # List existing symlinks only
gh-syms django clean                  # Remove all symlinks for django* dirs
gh-syms django --no-strict-nums-only  # Also process django-old, django_bak, etc.
```

### Terminal Output

Terminal output uses ANSI-colored status icons for quick visual scanning. The `#number` for each PR or issue is a clickable hyperlink in supported terminals (iTerm2, Terminal.app, Warp, etc.).

### PR Status Emoji (Slack)

Each line is formatted as: `date emoji title #number`. PRs use these status emoji:

| Emoji | State |
|---|---|
| `:git--merged:` | Merged |
| `:git--closed:` | Closed |
| `:git--draft:` | Draft |
| `:git--approved:` | Approved |
| `:git--changes-required:` | Changes requested |
| `:git--ready-for-review:` | Ready for review |

### Issue Status Emoji (Slack)

Issues use these status emoji:

| Emoji | State |
|---|---|
| `:git--issue:` | Open |
| `:git--closed:` | Closed |

## How It Works

1. Fetches PR/issue data as JSON via `gh`
2. Transforms it with `jq` into HTML (with `<a>` links) and plain text
3. Copies both formats to the macOS clipboard using an inline Swift snippet — Slack preserves hyperlinks from the HTML pasteboard type

## License

MIT
