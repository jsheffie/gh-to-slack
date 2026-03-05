# gh-to-slack

macOS shell script that formats GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copies it to the clipboard for pasting into Slack with clickable links and custom emoji.

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

2. Download the script and make executable:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/jsheffie/gh-to-slack/0.8/scripts/gh-to-slack-pasteboard.sh \
     -o ~/bin/gh-to-slack-pasteboard && chmod +x ~/bin/gh-to-slack-pasteboard
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

- macOS (uses `NSPasteboard` via Swift for clipboard access)
- [`gh`](https://cli.github.com/) CLI (authenticated)
- [`jq`](https://jqlang.github.io/jq/)
- Swift runtime (ships with Xcode / Command Line Tools)

## Usage

List your recent PRs or issues formatted for Slack. Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

```bash
gh-to-slack-pasteboard pr                    # Open, ready-for-review PRs
gh-to-slack-pasteboard pr --all              # All PRs
gh-to-slack-pasteboard pr 12595 12593        # Specific PRs
gh-to-slack-pasteboard issue                 # Open issues assigned to me
gh-to-slack-pasteboard issue --all           # All issues
gh-to-slack-pasteboard issue 42 57           # Specific issues
gh-to-slack-pasteboard pr --user octocat          # Open PRs by octocat
gh-to-slack-pasteboard issue --user bob --user ben # Issues for multiple users
gh-to-slack-pasteboard pr --limit 20              # Up to 20 PRs
gh-to-slack-pasteboard activity                   # Recent issues & PRs
gh-to-slack-pasteboard activity --user-display    # With linked usernames
gh-to-slack-pasteboard activity --limit 5         # 5 items per section
gh-to-slack-pasteboard users                      # List collaborators with links
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
