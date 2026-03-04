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

Options:
  --all       Show all items (merged, closed, draft, etc.)
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
EOF
  exit 0
}

if ! gh repo view --json name >/dev/null 2>&1; then
  echo "Error: not in a GitHub repository. Run this from inside a repo." >&2
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Error: subcommand required (pr or issue)." >&2
  echo "" >&2
  cat >&2 <<EOF
Usage: $(basename "$0") <pr|issue> [OPTIONS] [NUMBER ...]
Run '$(basename "$0") --help' for more information.
EOF
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
    cat >&2 <<EOF
Usage: $(basename "$0") <pr|issue> [OPTIONS] [NUMBER ...]
Run '$(basename "$0") --help' for more information.
EOF
    exit 1
    ;;
esac

# ── Subcommand-specific configuration ────────────────────────────────

if [ "$subcommand" = "pr" ]; then
  gh_cmd="pr"
  gh_list_filter="--author @me"
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
  gh_list_filter="--assignee @me"
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
    $gh_list_filter \
    --limit 10 \
    --state all \
    --json "$json_fields")
else
  json=$(gh "$gh_cmd" list \
    $gh_list_filter \
    --limit 10 \
    --state open \
    --json "$json_fields")
fi
