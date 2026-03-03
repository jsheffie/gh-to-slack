#!/usr/bin/env bash
# List your recent PRs formatted for pasting into Slack.
# Copies rich text to clipboard — Cmd+V into Slack gives clickable PR links.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [PR_NUMBER ...]

List your recent PRs formatted for pasting into Slack.
Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

Options:
  --all       Show all PRs (merged, closed, draft, etc.)
              Default shows only open, ready-for-review PRs.
  -h, --help  Show this help message and exit.

Arguments:
  PR_NUMBER   One or more PR numbers to show (e.g. 12595 12593 12590).
              When specified, --all is ignored.

Examples:
  $(basename "$0")                  # Open, ready-for-review PRs
  $(basename "$0") --all            # All PRs (merged, closed, draft, etc.)
  $(basename "$0") 12595 12593      # Specific PRs by number
EOF
  exit 0
}

show_all=false
pr_numbers=()

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --all) show_all=true ;;
    *) pr_numbers+=("$arg") ;;
  esac
done

JQ_EMOJI='
  (
    if .state == "MERGED" then ":git--merged:"
    elif .state == "CLOSED" then ":git--closed:"
    elif .isDraft then ":git--draft:"
    elif .reviewDecision == "APPROVED" then ":git--approved:"
    elif .reviewDecision == "CHANGES_REQUESTED" then ":git--changes-required:"
    else ":git--ready-for-review:"
    end
  ) as $emoji |
  (.updatedAt | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | . - 21600 | strftime("%b %d %I:%M%p")
    | sub("^(?<pre>.* )0"; "\(.pre)")
    | sub("(?<h>[0-9]+:[0-9]+)(?<p>AM|PM)"; "\(.h)\(.p | ascii_downcase)")
  ) as $updated'

if [ ${#pr_numbers[@]} -gt 0 ]; then
  # Fetch each specified PR individually and combine into a JSON array
  json="["
  first=true
  for pr in "${pr_numbers[@]}"; do
    pr_json=$(gh pr view "$pr" --json number,title,url,state,isDraft,reviewDecision,updatedAt)
    if [ "$first" = true ]; then
      first=false
    else
      json+=","
    fi
    json+="$pr_json"
  done
  json+="]"
elif [ "$show_all" = true ]; then
  json=$(gh pr list \
    --author @me \
    --limit 10 \
    --state all \
    --json number,title,url,state,isDraft,reviewDecision,updatedAt)
else
  # Default: open PRs (including drafts)
  json=$(gh pr list \
    --author @me \
    --limit 10 \
    --state open \
    --json number,title,url,state,isDraft,reviewDecision,updatedAt)
fi

# Build HTML (with <a> links) and plain text
html=$(echo "$json" | jq -r "[.[] | ${JQ_EMOJI} | \"\(\$emoji) \(.title) <a href=\\\"\(.url)\\\">#\(.number)</a>  \(\$updated)\"] | join(\"<br>\")")
plain=$(echo "$json" | jq -r ".[] | ${JQ_EMOJI} | \"\(\$emoji) \(.title) #\(.number)  \(\$updated)\"")

# Copy HTML to clipboard as public.html type (Slack preserves hyperlinks from this)
export PR_HTML="$html"
export PR_PLAIN="$plain"
swift -e '
import AppKit
let html = ProcessInfo.processInfo.environment["PR_HTML"]!
let plain = ProcessInfo.processInfo.environment["PR_PLAIN"]!
let pb = NSPasteboard.general
pb.clearContents()
pb.setString(html, forType: .html)
pb.setString(plain, forType: .string)
'

# Print preview to terminal
echo "$plain"
echo ""
echo "Copied to clipboard — Cmd+V into Slack for clickable links"
