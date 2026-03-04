#!/usr/bin/env bash
# List your recent issues formatted for pasting into Slack.
# Copies rich text to clipboard — Cmd+V into Slack gives clickable issue links.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [ISSUE_NUMBER ...]

List your recent issues formatted for pasting into Slack.
Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

Options:
  --all       Show all issues (open and closed).
              Default shows only open issues assigned to you.
  -h, --help  Show this help message and exit.

Arguments:
  ISSUE_NUMBER  One or more issue numbers to show (e.g. 42 57).
                When specified, --all is ignored.

Examples:
  $(basename "$0")                  # Open issues assigned to me
  $(basename "$0") --all            # All issues (open + closed)
  $(basename "$0") 42 57            # Specific issues by number
EOF
  exit 0
}

if ! gh repo view --json name >/dev/null 2>&1; then
  echo "Error: not in a GitHub repository. Run this from inside a repo." >&2
  exit 1
fi

show_all=false
issue_numbers=()

for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --all) show_all=true ;;
    *) issue_numbers+=("$arg") ;;
  esac
done

JQ_EMOJI='
  (
    if .state == "CLOSED" then ":git--closed:"
    else ":git--issue:"
    end
  ) as $emoji |
  (.updatedAt | sub("\\.[0-9]+Z$"; "Z") | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime | . - 21600 | strftime("%b %d %I:%M%p")
    | sub("^(?<pre>.* )0"; "\(.pre)")
    | sub("(?<h>[0-9]+:[0-9]+)(?<p>AM|PM)"; "\(.h)\(.p | ascii_downcase)")
  ) as $updated'

if [ ${#issue_numbers[@]} -gt 0 ]; then
  json="["
  first=true
  for issue in "${issue_numbers[@]}"; do
    issue_json=$(gh issue view "$issue" --json number,title,url,state,updatedAt)
    if [ "$first" = true ]; then
      first=false
    else
      json+=","
    fi
    json+="$issue_json"
  done
  json+="]"
elif [ "$show_all" = true ]; then
  json=$(gh issue list \
    --assignee @me \
    --limit 10 \
    --state all \
    --json number,title,url,state,updatedAt)
else
  json=$(gh issue list \
    --assignee @me \
    --limit 10 \
    --state open \
    --json number,title,url,state,updatedAt)
fi

html=$(echo "$json" | jq -r "[.[] | ${JQ_EMOJI} | \"\(\$emoji) \(.title) <a href=\\\"\(.url)\\\">#\(.number)</a>  \(\$updated)\"] | join(\"<br>\")")
plain=$(echo "$json" | jq -r ".[] | ${JQ_EMOJI} | \"\(\$emoji) \(.title) #\(.number)  \(\$updated)\"")

export ISSUE_HTML="$html"
export ISSUE_PLAIN="$plain"
swift -e '
import AppKit
let html = ProcessInfo.processInfo.environment["ISSUE_HTML"]!
let plain = ProcessInfo.processInfo.environment["ISSUE_PLAIN"]!
let pb = NSPasteboard.general
pb.clearContents()
pb.setString(html, forType: .html)
pb.setString(plain, forType: .string)
'

echo "$plain"
echo ""
echo "Copied to clipboard — Cmd+V into Slack for clickable links"
