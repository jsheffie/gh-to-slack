#!/usr/bin/env bash
# Format GitHub PRs or issues for pasting into Slack.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <pr|issue> [OPTIONS] [NUMBER ...]

Format GitHub PRs or issues for pasting into Slack.
Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

Subcommands:
  pr          List PRs authored by you.
  issue       List issues assigned to you.
  users       List repository collaborators with links to issues and PRs.

Options:
  --all       Show all items regardless of state (open, closed, merged, etc.)
              Default shows only open items.
  -h, --help  Show this help message and exit.

Arguments:
  NUMBER      One or more PR/issue numbers to show (e.g. 12595 12593).
              When specified, --all is ignored.

Examples:
  $(basename "$0") pr                    # Open, ready-for-review PRs
  $(basename "$0") pr --all              # All PRs (merged, closed, draft, etc.)
  $(basename "$0") pr 12595 12593        # Specific PRs by number
  $(basename "$0") issue                 # Open issues assigned to me
  $(basename "$0") issue --all           # All issues (open + closed)
  $(basename "$0") issue 42 57           # Specific issues by number
  $(basename "$0") users                   # List collaborators with links
EOF
  exit 0
}

if ! gh repo view --json name >/dev/null 2>&1; then
  echo "Error: not in a GitHub repository. Run this from inside a repo." >&2
  exit 1
fi

usage_hint() {
  echo "Usage: $(basename "$0") <pr|issue> [OPTIONS] [NUMBER ...]" >&2
  echo "Run '$(basename "$0") --help' for more information." >&2
}

if [ $# -eq 0 ]; then
  echo "Error: subcommand required (pr or issue)." >&2
  echo "" >&2
  usage_hint
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
  pr|issue)
    # Valid subcommand — continue
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Error: unknown subcommand '$subcommand'." >&2
    echo "" >&2
    usage_hint
    exit 1
    ;;
esac

# ── Subcommand-specific configuration ────────────────────────────────

if [ "$subcommand" = "pr" ]; then
  gh_cmd="pr"
  gh_list_filter=(--author @me)
  json_fields="number,title,url,state,isDraft,reviewDecision,updatedAt"

  JQ_SLACK_EMOJI='
    (
      if .state == "MERGED" then ":git--merged:"
      elif .state == "CLOSED" then ":git--closed:"
      elif .isDraft then ":git--draft:"
      elif .reviewDecision == "APPROVED" then ":git--approved:"
      elif .reviewDecision == "CHANGES_REQUESTED" then ":git--changes-required:"
      else ":git--ready-for-review:"
      end
    ) as $emoji'

  JQ_TERMINAL_ICON='
    (
      if .state == "MERGED" then "\u001b[35m●\u001b[0m"
      elif .state == "CLOSED" then "\u001b[31m●\u001b[0m"
      elif .isDraft then "\u001b[90m●\u001b[0m"
      elif .reviewDecision == "APPROVED" then "\u001b[32m✓\u001b[0m"
      elif .reviewDecision == "CHANGES_REQUESTED" then "\u001b[33m!\u001b[0m"
      else "\u001b[33m●\u001b[0m"
      end
    ) as $icon'

else
  gh_cmd="issue"
  gh_list_filter=(--assignee @me)
  json_fields="number,title,url,state,updatedAt"

  JQ_SLACK_EMOJI='
    (
      if .state == "CLOSED" then ":git--closed:"
      else ":git--issue:"
      end
    ) as $emoji'

  JQ_TERMINAL_ICON='
    (
      if .state == "CLOSED" then "\u001b[31m●\u001b[0m"
      else "\u001b[33m●\u001b[0m"
      end
    ) as $icon'
fi

# ── Arg parsing ──────────────────────────────────────────────────────

show_all=false
numbers=()

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --all) show_all=true ;;
    *) numbers+=("$arg") ;;
  esac
done

# ── JSON fetching ────────────────────────────────────────────────────

if [ ${#numbers[@]} -gt 0 ]; then
  # Fetch each specified item individually and combine into a JSON array
  json="["
  first=true
  for num in "${numbers[@]}"; do
    item_json=$(gh "$gh_cmd" view "$num" --json "$json_fields")
    if [ "$first" = true ]; then
      first=false
    else
      json+=","
    fi
    json+="$item_json"
  done
  json+="]"
elif [ "$show_all" = true ]; then
  json=$(gh "$gh_cmd" list \
    "${gh_list_filter[@]}" \
    --limit 10 \
    --state all \
    --json "$json_fields")
else
  json=$(gh "$gh_cmd" list \
    "${gh_list_filter[@]}" \
    --limit 10 \
    --state open \
    --json "$json_fields")
fi

# ── Output generation ────────────────────────────────────────────────

JQ_TIMESTAMP='
  (.updatedAt | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | . - 21600 | strftime("%b %d %I:%M%p")
    | sub("(?<h>[0-9]+:[0-9]+)(?<p>AM|PM)"; "\(.h)\(.p | ascii_downcase)")
  ) as $updated'

# HTML with <a> links + Slack emoji (for clipboard rich text)
# <code>\($updated)</code> \($emoji)
html=$(echo "$json" | jq -r "[sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"<code>\(\$updated)</code> \(\$emoji) \(.title) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")

# Plain text with Slack emoji (clipboard fallback)
slack_plain=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"\`\(\$updated)\` \(\$emoji) \(.title) #\(.number)\"")

# Terminal output with ANSI colored icons and OSC 8 clickable links
terminal_plain=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_TERMINAL_ICON} | ${JQ_TIMESTAMP} | \"\(\$updated) \(\$icon) \(.title) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")

# ── Clipboard ────────────────────────────────────────────────────────

export CLIPBOARD_HTML="$html"
export CLIPBOARD_PLAIN="$slack_plain"
swift -e '
import AppKit
let html = ProcessInfo.processInfo.environment["CLIPBOARD_HTML"]!
let plain = ProcessInfo.processInfo.environment["CLIPBOARD_PLAIN"]!
let pb = NSPasteboard.general
pb.clearContents()
pb.setString(html, forType: .html)
pb.setString(plain, forType: .string)
'

# ── Terminal display ─────────────────────────────────────────────────

printf '%s\n' "$terminal_plain"
echo ""
echo "Copied to clipboard — Cmd+V into Slack for clickable links"
