# gh-to-slack

macOS shell scripts that format GitHub CLI (`gh`) output (PRs, issues, etc.) into rich text and copy it to the clipboard for pasting into Slack with clickable links and custom emoji.

## Install

1. Create `~/bin` if it doesn't exist:

   ```bash
   mkdir -p ~/bin
   ```

2. Download the script(s) and make executable:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/jsheffie/gh-to-slack/0.1/scripts/gh-pr-to-slack.sh \
     -o ~/bin/gh-pr-to-slack && chmod +x ~/bin/gh-pr-to-slack

   curl -fsSL https://raw.githubusercontent.com/jsheffie/gh-to-slack/0.1/scripts/gh-issue-to-slack.sh \
     -o ~/bin/gh-issue-to-slack && chmod +x ~/bin/gh-issue-to-slack
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

### gh-pr-to-slack

List your recent PRs formatted for Slack. Copies rich text to clipboard — Cmd+V into Slack gives clickable PR links.

```bash
# Open, ready-for-review PRs authored by you
gh-pr-to-slack

# All PRs (merged, closed, draft, etc.)
gh-pr-to-slack --all

# Specific PRs by number
gh-pr-to-slack 12595 12593
```

Each PR is prefixed with a status emoji:

| Emoji | State |
|---|---|
| `:git--merged:` | Merged |
| `:git--closed:` | Closed |
| `:git--draft:` | Draft |
| `:git--approved:` | Approved |
| `:git--changes-required:` | Changes requested |
| `:git--ready-for-review:` | Ready for review |

### gh-issue-to-slack

List your recent issues formatted for Slack. Copies rich text to clipboard — Cmd+V into Slack gives clickable issue links.

```bash
# Open issues assigned to you
gh-issue-to-slack

# All issues (open + closed)
gh-issue-to-slack --all

# Specific issues by number
gh-issue-to-slack 42 57
```

Each issue is prefixed with a status emoji:

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
