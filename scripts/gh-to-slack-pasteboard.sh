#!/usr/bin/env bash
# Format GitHub PRs or issues for pasting into Slack.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <pr|issue|users> [OPTIONS] [NUMBER ...]

Format GitHub PRs or issues for pasting into Slack.
Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

Subcommands:
  pr          List PRs authored by you.
  issue       List issues assigned to you.
  users       List repository collaborators with links to issues and PRs.

Options:
  --user USER Filter by GitHub user (repeatable, default: @me).
  --limit N   Max items per user (default: 10).
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
  $(basename "$0") pr --user octocat          # Open PRs by octocat
  $(basename "$0") issue --user bob --user ben # Issues for multiple users
  $(basename "$0") pr --limit 20              # Open PRs, up to 20
  $(basename "$0") users                   # List collaborators with links
EOF
  exit 0
}

if ! gh repo view --json name >/dev/null 2>&1; then
  echo "Error: not in a GitHub repository. Run this from inside a repo." >&2
  exit 1
fi

usage_hint() {
  echo "Usage: $(basename "$0") <pr|issue|users> [OPTIONS] [NUMBER ...]" >&2
  echo "Run '$(basename "$0") --help' for more information." >&2
}

if [ $# -eq 0 ]; then
  echo "Error: subcommand required (pr, issue, or users)." >&2
  echo "" >&2
  usage_hint
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
  pr|issue|users)
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

# ── Users subcommand (short-circuit) ──────────────────────────────────

if [ "$subcommand" = "users" ]; then
  repo_slug=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
  repo_url="https://github.com/${repo_slug}"

  users=$(gh api "repos/${repo_slug}/collaborators" --jq '.[].login' | sort)

  if [ -z "$users" ]; then
    echo "No collaborators found." >&2
    exit 0
  fi

  html=""
  slack_plain=""
  terminal_plain=""

  while IFS= read -r user; do
    created_url="${repo_url}/issues/created_by/${user}"
    assigned_url="${repo_url}/issues?q=assignee%3A${user}+is%3Aopen+"
    prs_url="${repo_url}/pulls/${user}"

    # HTML for Slack clipboard
    line=":technologist: ${user}"
    line+=" <a href=\"${created_url}\">created issues</a>"
    line+=" | <a href=\"${assigned_url}\">assigned issues</a>"
    line+=" | <a href=\"${prs_url}\">PRs</a>"
    if [ -n "$html" ]; then html+="<br>"; fi
    html+="$line"

    # Plain text fallback for clipboard
    plain_line=":technologist: ${user}  created issues | assigned issues | PRs"
    if [ -n "$slack_plain" ]; then slack_plain+=$'\n'; fi
    slack_plain+="$plain_line"

    # Terminal with OSC 8 hyperlinks (using printf with \033 escapes, matching pr/issue format)
    osc_line=$(printf ':technologist: %s  \033]8;;%s\033\\created issues\033]8;;\033\\ | \033]8;;%s\033\\assigned issues\033]8;;\033\\ | \033]8;;%s\033\\PRs\033]8;;\033\\' "$user" "$created_url" "$assigned_url" "$prs_url")
    if [ -n "$terminal_plain" ]; then terminal_plain+=$'\n'; fi
    terminal_plain+="$osc_line"
  done <<< "$users"

  # Copy to clipboard
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

  # Terminal display
  printf '%s\n' "$terminal_plain"
  echo ""
  echo "Copied to clipboard — Cmd+V into Slack for clickable links"
  exit 0
fi

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
limit=10
users=()
user_explicit=false

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --all) show_all=true ;;
    --limit)
      shift
      if [ $# -eq 0 ]; then
        echo "Error: --limit requires a number." >&2
        exit 1
      fi
      if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: --limit must be a positive integer, got '$1'." >&2
        exit 1
      fi
      limit="$1"
      ;;
    --user)
      shift
      if [ $# -eq 0 ]; then
        echo "Error: --user requires a username." >&2
        exit 1
      fi
      users+=("$1")
      user_explicit=true
      ;;
    *) numbers+=("$1") ;;
  esac
  shift
done

if [ ${#users[@]} -gt 1 ] && [ ${#numbers[@]} -gt 0 ]; then
  echo "Error: cannot combine multiple --user with specific numbers." >&2
  exit 1
fi

# Generate header line for a user across all three output formats.
# Sets: header_html, header_plain, header_terminal
build_user_header() {
  local user="$1"
  local label
  if [ "$subcommand" = "pr" ]; then
    label="PRs"
  else
    label="Issues"
  fi
  local profile_url="https://github.com/${user}"
  header_html=":technologist: ${label} for <a href=\"${profile_url}\">@${user}</a>"
  header_plain=":technologist: ${label} for @${user}"
  header_terminal=$(printf ':technologist: %s for \033]8;;%s\033\\@%s\033]8;;\033\\' "$label" "$profile_url" "$user")
}

# ── Output generation ────────────────────────────────────────────────

JQ_TIMESTAMP='
  (.updatedAt | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | . - 21600 | strftime("%b %d %I:%M%p")
    | sub("(?<h>[0-9]+:[0-9]+)(?<p>AM|PM)"; "\(.h)\(.p | ascii_downcase)")
  ) as $updated'

if [ "$user_explicit" = true ] && [ ${#users[@]} -gt 0 ]; then
  # ── Per-user loop ───────────────────────────────────────────────────
  all_html=""
  all_slack_plain=""
  all_terminal_plain=""

  for user in "${users[@]}"; do
    # Set filter for this user
    if [ "$subcommand" = "pr" ]; then
      gh_list_filter=(--author "$user")
    else
      gh_list_filter=(--assignee "$user")
    fi

    # Fetch JSON for this user
    if [ ${#numbers[@]} -gt 0 ]; then
      # Single user + numbers (validated: only 1 user allowed with numbers)
      json="["
      first=true
      for num in "${numbers[@]}"; do
        item_json=$(gh "$gh_cmd" view "$num" --json "$json_fields")
        if [ "$first" = true ]; then first=false; else json+=","; fi
        json+="$item_json"
      done
      json+="]"
    elif [ "$show_all" = true ]; then
      json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit "$limit" --state all --json "$json_fields")
    else
      json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit "$limit" --state open --json "$json_fields")
    fi

    # Build header
    build_user_header "$user"

    # Generate formatted output for this user's items
    user_html=$(echo "$json" | jq -r "[sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"<code>\(\$updated)</code> \(\$emoji) \(.title) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")
    user_slack=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"\`\(\$updated)\` \(\$emoji) \(.title) #\(.number)\"")
    user_terminal=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_TERMINAL_ICON} | ${JQ_TIMESTAMP} | \"\(\$updated) \(\$icon) \(.title) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")

    # Prepend header
    user_html="${header_html}<br>${user_html}"
    user_slack="${header_plain}"$'\n'"${user_slack}"
    user_terminal="${header_terminal}"$'\n'"${user_terminal}"

    # Accumulate with blank line separator
    if [ -n "$all_html" ]; then
      all_html+="<br><br>"
      all_slack_plain+=$'\n\n'
      all_terminal_plain+=$'\n\n'
    fi
    all_html+="$user_html"
    all_slack_plain+="$user_slack"
    all_terminal_plain+="$user_terminal"
  done

  html="$all_html"
  slack_plain="$all_slack_plain"
  terminal_plain="$all_terminal_plain"
else
  # ── Default path (no --user, same as today) ─────────────────────────
  if [ ${#numbers[@]} -gt 0 ]; then
    json="["
    first=true
    for num in "${numbers[@]}"; do
      item_json=$(gh "$gh_cmd" view "$num" --json "$json_fields")
      if [ "$first" = true ]; then first=false; else json+=","; fi
      json+="$item_json"
    done
    json+="]"
  elif [ "$show_all" = true ]; then
    json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit "$limit" --state all --json "$json_fields")
  else
    json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit "$limit" --state open --json "$json_fields")
  fi

  html=$(echo "$json" | jq -r "[sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"<code>\(\$updated)</code> \(\$emoji) \(.title) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")
  slack_plain=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_SLACK_EMOJI} | ${JQ_TIMESTAMP} | \"\`\(\$updated)\` \(\$emoji) \(.title) #\(.number)\"")
  terminal_plain=$(echo "$json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_TERMINAL_ICON} | ${JQ_TIMESTAMP} | \"\(\$updated) \(\$icon) \(.title) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")
fi

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
