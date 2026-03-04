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
  usage_error=true
  # Print usage to stderr and exit 1
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
