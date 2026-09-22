#!/usr/bin/env bash
# Format GitHub PRs or issues for pasting into Slack.
# jq programs live in single quotes on purpose, and printf formats end in a
# literal backslash (OSC 8 terminator), so these checks are false positives.
# shellcheck disable=SC2016,SC1003

set -euo pipefail

VERSION="1.0.12"
RELEASES_URL="https://github.com/jsheffie/gh-to-slack/releases"

# Root that `<repodir>:<type>:<number>` arguments resolve under.
WORKSPACE_ROOT="${GH_CLIPPY_WORKSPACE:-$HOME/workspace}"

# ── Inline icon support ──────────────────────────────────────────────

# Resolve icon directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR=""
if [ -d "$(brew --prefix 2>/dev/null)/share/gh-to-slack/icons" ]; then
  ICON_DIR="$(brew --prefix)/share/gh-to-slack/icons"
elif [ -d "${SCRIPT_DIR}/../icons" ]; then
  ICON_DIR="${SCRIPT_DIR}/../icons"
fi

# Determine icon mode: inline (images) or text (ANSI fallback)
resolve_icon_mode() {
  case "${TERMINAL_ICONS:-}" in
    text)   echo "text" ;;
    inline) echo "inline" ;;
    *)
      case "${TERM_PROGRAM:-}" in
        iTerm.app|kitty|WezTerm) echo "inline" ;;
        *) echo "text" ;;
      esac
      ;;
  esac
}

ICON_MODE=$(resolve_icon_mode)

# Fall back to text if icon directory not found
if [ "$ICON_MODE" = "inline" ] && [ -z "$ICON_DIR" ]; then
  ICON_MODE="text"
fi

# Render an icon as either an inline image or ANSI text.
# Usage: render_icon <icon-name> <ansi-fallback>
render_icon() {
  local name="$1"
  local fallback="$2"

  if [ "$ICON_MODE" = "inline" ] && [ -f "${ICON_DIR}/${name}.png" ]; then
    local b64
    b64=$(base64 < "${ICON_DIR}/${name}.png")
    printf '\033]1337;File=inline=1;width=2;height=1;preserveAspectRatio=1:%s\a' "$b64"
  else
    printf '%b' "$fallback"
  fi
}

# Pre-compute icon strings for jq injection
ICON_PR_MERGED=$(render_icon "pr-merged" "\033[35m●\033[0m")
ICON_PR_CLOSED=$(render_icon "pr-closed" "\033[31m●\033[0m")
ICON_PR_DRAFT=$(render_icon "pr-draft" "\033[90m●\033[0m")
ICON_PR_APPROVED=$(render_icon "pr-approved" "\033[32m✓\033[0m")
ICON_PR_CHANGES=$(render_icon "pr-changes-requested" "\033[33m!\033[0m")
ICON_PR_READY=$(render_icon "pr-ready-for-review" "\033[33m●\033[0m")
ICON_ISSUE_OPEN=$(render_icon "issue-open" "\033[33m●\033[0m")
ICON_ISSUE_CLOSED=$(render_icon "issue-closed" "\033[31m●\033[0m")
ICON_TECHNOLOGIST=$(render_icon "technologist" ":technologist:")

usage() {
  cat <<EOF
Usage: $(basename "$0") <pr|issue|stack|activity|users> [OPTIONS] [NUMBER|SPEC ...]

Format GitHub PRs or issues for pasting into Slack.
Copies rich text to clipboard — Cmd+V into Slack gives clickable links.

Subcommands:
  pr          List PRs authored by you.
  issue       List issues assigned to you.
  stack       List the PRs of a gh-stack (github/gh-stack), in stack order.
              Reads "gh stack view --json" from stdin when piped, otherwise
              runs it in the current repo.
  users       List repository collaborators with links to issues and PRs.
  activity    Show recent issues and PRs across the repo.

Options:
  --user USER Filter by GitHub user (repeatable, default: @me).
  --limit N   Max items per user (default: 10).
  --all       Show all items regardless of state (open, closed, merged, etc.)
              Default shows only open items.
  --teams     Output a rich-text table (Status | Title | Link) for pasting
              into MS Teams, instead of Slack rich text. (pr/issue/stack only)
  --version   Show version and exit.
  -h, --help  Show this help message and exit.

Arguments:
  NUMBER      One or more PR/issue numbers in the current repo (e.g. 12595).
              When specified, --all and --limit are ignored and items print
              in the order listed.
  SPEC        An item in another repo: <repodir>:<pr|issue>:<number>, e.g.
              django:pr:100. The repo dir resolves under ~/workspace
              (override with GH_CLIPPY_WORKSPACE). Specs and numbers may be
              mixed; PRs and issues may be mixed. Cannot combine with --user.
              SPEC works from any directory; bare NUMBER requires the
              current directory to be a GitHub repo.

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
  gh stack view --json | $(basename "$0") stack   # Stack PRs, piped
  $(basename "$0") stack                   # Stack PRs, self-fetched
  $(basename "$0") users                   # List collaborators with links
  $(basename "$0") activity                # Recent issues & PRs
  $(basename "$0") activity --user-display # With usernames shown
  $(basename "$0") activity --limit 5      # 5 items per section
  $(basename "$0") pr --teams              # Rich-text table for MS Teams
  $(basename "$0") pr django:pr:100                  # PR from another repo
  $(basename "$0") pr django:pr:100 myrepo:issue:42   # Mixed, in listed order
EOF
  exit 0
}

usage_hint() {
  echo "Usage: $(basename "$0") <pr|issue|stack|activity|users> [OPTIONS] [NUMBER|SPEC ...]" >&2
  echo "Run '$(basename "$0") --help' for more information." >&2
}

if [ $# -eq 0 ]; then
  echo "Error: subcommand required (pr, issue, stack, activity, or users)." >&2
  echo "" >&2
  usage_hint
  exit 1
fi

subcommand="$1"
shift

case "$subcommand" in
  pr|issue|stack|activity|users)
    # Valid subcommand — continue
    ;;
  -h|--help)
    usage
    ;;
  --version)
    readme_url="https://github.com/jsheffie/gh-to-slack"
    printf '\ngh-clippy %s\n\n' "${VERSION}"
    printf 'Check \033]8;;%s\033\\gh-to-slack releases\033]8;;\033\\. If you are not on the latest version\nsee \033]8;;%s\033\\README\033]8;;\033\\ for install upgrade instructions\n\n' "${RELEASES_URL}" "${readme_url}"
    exit 0
    ;;
  *)
    echo "Error: unknown subcommand '$subcommand'." >&2
    echo "" >&2
    usage_hint
    exit 1
    ;;
esac

# ── Stray-stdin guard ────────────────────────────────────────────────
# Only `stack` reads stdin. Piping into any other subcommand would otherwise
# discard the input silently and print that subcommand's normal listing —
# output that looks plausible but answers a different question.
if [ "$subcommand" != "stack" ] && [ -p /dev/fd/0 ]; then
  echo "Error: '${subcommand}' does not read stdin." >&2
  if head -c 200 /dev/fd/0 2>/dev/null | grep -q '"branches"'; then
    echo "That looks like 'gh stack view --json' — did you mean:" >&2
    echo "  gh stack view --json | $(basename "$0") stack" >&2
  else
    echo "Only '$(basename "$0") stack' accepts piped input." >&2
  fi
  exit 1
fi

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

  # Collect users into array and find max username length for column alignment
  user_list=()
  while IFS= read -r u; do
    user_list+=("$u")
  done <<< "$users"

  max_name_len=0
  for u in "${user_list[@]}"; do
    if [ "${#u}" -gt "$max_name_len" ]; then
      max_name_len="${#u}"
    fi
  done

  for user in "${user_list[@]}"; do
    created_url="${repo_url}/issues/created_by/${user}"
    assigned_url="${repo_url}/issues?q=assignee%3A${user}+is%3Aopen+"
    prs_url="${repo_url}/pulls/${user}"

    # Compute padding so all "created issues" links start at the same column
    pad=$(( max_name_len - ${#user} ))
    pad_str=$(printf '%*s' "$pad" '')

    # HTML for Slack clipboard
    profile_url="https://github.com/${user}"
    line=":technologist: <a href=\"${profile_url}\">${user}</a>${pad_str}"
    line+=" <a href=\"${created_url}\">created issues</a>"
    line+=" | <a href=\"${assigned_url}\">assigned issues</a>"
    line+=" | <a href=\"${prs_url}\">PRs</a>"
    if [ -n "$html" ]; then html+="<br>"; fi
    html+="$line"

    # Plain text fallback for clipboard (padded for monospace display in Slack)
    plain_line=":technologist: $(printf '%-*s' "$max_name_len" "$user")  created issues | assigned issues | PRs"
    if [ -n "$slack_plain" ]; then slack_plain+=$'\n'; fi
    slack_plain+="$plain_line"

    # Terminal with OSC 8 hyperlinks and padding after username
    osc_line="${ICON_TECHNOLOGIST} "$(printf '\033]8;;%s\033\\%s\033]8;;\033\\%s  \033]8;;%s\033\\created issues\033]8;;\033\\ | \033]8;;%s\033\\assigned issues\033]8;;\033\\ | \033]8;;%s\033\\PRs\033]8;;\033\\' "$profile_url" "$user" "$pad_str" "$created_url" "$assigned_url" "$prs_url")
    if [ -n "$terminal_plain" ]; then terminal_plain+=$'\n'; fi
    terminal_plain+="$osc_line"
  done

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

# ── Activity subcommand (short-circuit) ──────────────────────────────

if [ "$subcommand" = "activity" ]; then
  # Parse activity-specific args
  limit=10
  user_display=false

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage ;;
      --user-display) user_display=true ;;
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
      *)
        echo "Error: activity does not accept '$1'. Only --user-display and --limit are supported." >&2
        exit 1
        ;;
    esac
    shift
  done

  # ── Fetch issues ───────────────────────────────────────────────────

  issue_json=$(gh issue list --limit "$limit" --state all --json "number,title,url,state,updatedAt,assignees")

  JQ_ISSUE_EMOJI='
    (
      if .state == "CLOSED" then ":git--closed:"
      else ":git--issue:"
      end
    ) as $emoji'

  JQ_ISSUE_ICON='
    (
      if .state == "CLOSED" then $icon_issue_closed
      else $icon_issue_open
      end
    ) as $icon'

  if [ "$user_display" = true ]; then
    JQ_ISSUE_USER_HTML='(if (.assignees | length) > 0 then " <a href=\"https://github.com/" + .assignees[0].login + "\">@" + .assignees[0].login + "</a>" else "" end) as $user'
    JQ_ISSUE_USER_PLAIN='(if (.assignees | length) > 0 then " @" + .assignees[0].login else "" end) as $user'
    JQ_ISSUE_USER_TERM='(if (.assignees | length) > 0 then " \u001b]8;;https://github.com/" + .assignees[0].login + "\u001b\\@" + .assignees[0].login + "\u001b]8;;\u001b\\" else "" end) as $user'
  else
    JQ_ISSUE_USER_HTML='"" as $user'
    JQ_ISSUE_USER_PLAIN='"" as $user'
    JQ_ISSUE_USER_TERM='"" as $user'
  fi

  issue_html=$(echo "$issue_json" | jq -r "[sort_by(.updatedAt) | reverse | .[] | ${JQ_ISSUE_EMOJI} | ${JQ_ISSUE_USER_HTML} | (.title | gsub(\"<\";\"&lt;\") | gsub(\">\";\"&gt;\")) as \$safe_title | \"\(\$emoji) \(\$safe_title)\(\$user) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")
  issue_plain=$(echo "$issue_json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_ISSUE_EMOJI} | ${JQ_ISSUE_USER_PLAIN} | \"\(\$emoji) \(.title)\(\$user) #\(.number)\"")
  issue_terminal=$(echo "$issue_json" | jq -r \
    --arg icon_issue_open "$ICON_ISSUE_OPEN" \
    --arg icon_issue_closed "$ICON_ISSUE_CLOSED" \
    "sort_by(.updatedAt) | reverse | .[] | ${JQ_ISSUE_ICON} | ${JQ_ISSUE_USER_TERM} | \"\(\$icon) \(.title)\(\$user) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")

  # ── Fetch PRs ──────────────────────────────────────────────────────

  pr_json=$(gh pr list --limit "$limit" --state all --json "number,title,url,state,isDraft,reviewDecision,updatedAt,author")

  JQ_PR_EMOJI='
    (
      if .state == "MERGED" then ":git--merged:"
      elif .state == "CLOSED" then ":git--closed:"
      elif .isDraft then ":git--draft:"
      elif .reviewDecision == "APPROVED" then ":git--approved:"
      elif .reviewDecision == "CHANGES_REQUESTED" then ":git--changes-required:"
      else ":git--ready-for-review:"
      end
    ) as $emoji'

  JQ_PR_ICON='
    (
      if .state == "MERGED" then $icon_merged
      elif .state == "CLOSED" then $icon_closed
      elif .isDraft then $icon_draft
      elif .reviewDecision == "APPROVED" then $icon_approved
      elif .reviewDecision == "CHANGES_REQUESTED" then $icon_changes
      else $icon_ready
      end
    ) as $icon'

  if [ "$user_display" = true ]; then
    JQ_PR_USER_HTML='(" <a href=\"https://github.com/" + .author.login + "\">@" + .author.login + "</a>") as $user'
    JQ_PR_USER_PLAIN='(" @" + .author.login) as $user'
    JQ_PR_USER_TERM='(" \u001b]8;;https://github.com/" + .author.login + "\u001b\\@" + .author.login + "\u001b]8;;\u001b\\") as $user'
  else
    JQ_PR_USER_HTML='"" as $user'
    JQ_PR_USER_PLAIN='"" as $user'
    JQ_PR_USER_TERM='"" as $user'
  fi

  pr_html=$(echo "$pr_json" | jq -r "[sort_by(.updatedAt) | reverse | .[] | ${JQ_PR_EMOJI} | ${JQ_PR_USER_HTML} | (.title | gsub(\"<\";\"&lt;\") | gsub(\">\";\"&gt;\")) as \$safe_title | \"\(\$emoji) \(\$safe_title)\(\$user) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")
  pr_plain=$(echo "$pr_json" | jq -r "sort_by(.updatedAt) | reverse | .[] | ${JQ_PR_EMOJI} | ${JQ_PR_USER_PLAIN} | \"\(\$emoji) \(.title)\(\$user) #\(.number)\"")
  pr_terminal=$(echo "$pr_json" | jq -r \
    --arg icon_merged "$ICON_PR_MERGED" \
    --arg icon_closed "$ICON_PR_CLOSED" \
    --arg icon_draft "$ICON_PR_DRAFT" \
    --arg icon_approved "$ICON_PR_APPROVED" \
    --arg icon_changes "$ICON_PR_CHANGES" \
    --arg icon_ready "$ICON_PR_READY" \
    "sort_by(.updatedAt) | reverse | .[] | ${JQ_PR_ICON} | ${JQ_PR_USER_TERM} | \"\(\$icon) \(.title)\(\$user) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")

  # ── Assemble sections ──────────────────────────────────────────────

  html=":git--issue: Issues<br>${issue_html}<br><br>:git--ready-for-review: PRs<br>${pr_html}"
  slack_plain=":git--issue: Issues"$'\n'"${issue_plain}"$'\n'$'\n'":git--ready-for-review: PRs"$'\n'"${pr_plain}"
  terminal_plain="${ICON_ISSUE_OPEN} Issues"$'\n'"${issue_terminal}"$'\n'$'\n'"${ICON_PR_READY} PRs"$'\n'"${pr_terminal}"

  # ── Clipboard ──────────────────────────────────────────────────────

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

  # ── Terminal display ───────────────────────────────────────────────

  printf '%s\n' "$terminal_plain"
  echo ""
  echo "Copied to clipboard — Cmd+V into Slack for clickable links"
  exit 0
fi

# ── Field sets per item kind ─────────────────────────────────────────
# `gh issue view --json isDraft` is an error, so PRs and issues must be
# fetched with different field sets and then tagged with `kind`.
PR_JSON_FIELDS="number,title,url,state,isDraft,reviewDecision"
ISSUE_JSON_FIELDS="number,title,url,state"

# ── Subcommand-specific configuration ────────────────────────────────
# Applies to list mode and to bare numeric arguments.

if [ "$subcommand" = "pr" ] || [ "$subcommand" = "stack" ]; then
  gh_cmd="pr"
  gh_list_filter=(--author @me)
  json_fields="$PR_JSON_FIELDS"
else
  gh_cmd="issue"
  gh_list_filter=(--assignee @me)
  json_fields="$ISSUE_JSON_FIELDS"
fi

# ── Presentation, dispatched per item kind ───────────────────────────
# A single list may hold both PRs and issues, so these branch on .kind
# rather than on the subcommand.

JQ_SLACK_EMOJI='
  (
    if .kind == "pr" then
      (if .state == "MERGED" then ":git--merged:"
       elif .state == "CLOSED" then ":git--closed:"
       elif .isDraft then ":git--draft:"
       elif .reviewDecision == "APPROVED" then ":git--approved:"
       elif .reviewDecision == "CHANGES_REQUESTED" then ":git--changes-required:"
       else ":git--ready-for-review:"
       end)
    else
      (if .state == "CLOSED" then ":git--closed:"
       else ":git--issue:"
       end)
    end
  ) as $emoji'

JQ_TERMINAL_ICON='
  (
    if .kind == "pr" then
      (if .state == "MERGED" then $icon_merged
       elif .state == "CLOSED" then $icon_closed
       elif .isDraft then $icon_draft
       elif .reviewDecision == "APPROVED" then $icon_approved
       elif .reviewDecision == "CHANGES_REQUESTED" then $icon_changes
       else $icon_ready
       end)
    else
      (if .state == "CLOSED" then $icon_issue_closed
       else $icon_issue_open
       end)
    end
  ) as $icon'

JQ_TEAMS_STATUS='
  (
    if .kind == "pr" then
      (if .state == "MERGED" then "🟣 Merged"
       elif .state == "CLOSED" then "🔴 Closed"
       elif .isDraft then "⚪ Draft"
       elif .reviewDecision == "APPROVED" then "✅ Approved"
       elif .reviewDecision == "CHANGES_REQUESTED" then "❗ Changes requested"
       else "🟢 Ready"
       end)
    else
      (if .state == "CLOSED" then "🔴 Closed"
       else "🟢 Open"
       end)
    end
  ) as $status'

# Validate a `<repodir>:<pr|issue>:<number>` argument.
# Returns 1 if the argument contains no colon (i.e. it is a bare number).
# Exits 1 if it contains a colon but is malformed.
# On success sets: spec_dir, spec_type, spec_num
parse_spec() {
  local arg="$1"

  spec_dir=""; spec_type=""; spec_num=""

  case "$arg" in
    *:*) ;;
    *) return 1 ;;
  esac

  if ! [[ "$arg" =~ ^[^:/]+:(pr|issue):[0-9]+$ ]]; then
    echo "Error: invalid item spec '$arg'." >&2
    echo "Expected <repodir>:<pr|issue>:<number>, e.g. django:pr:100" >&2
    exit 1
  fi

  spec_dir="${arg%%:*}"
  spec_num="${arg##*:}"
  local middle="${arg#*:}"
  spec_type="${middle%%:*}"
}

# ── Arg parsing ──────────────────────────────────────────────────────

show_all=false
numbers=()
limit=10
limit_explicit=false
users=()
user_explicit=false
teams=false

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --all) show_all=true ;;
    --teams) teams=true ;;
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
      limit_explicit=true
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
    *)
      # Validates and exits on a malformed spec; bare numbers pass through.
      if parse_spec "$1"; then :; fi
      numbers+=("$1")
      ;;
  esac
  shift
done

# A stack is a fixed dependency chain: truncating it or filtering it by
# author would misrepresent the chain, and item specs name their own items.
if [ "$subcommand" = "stack" ]; then
  if [ ${#numbers[@]} -gt 0 ]; then
    echo "Error: stack takes no NUMBER or SPEC arguments." >&2
    exit 1
  fi
  if [ "$user_explicit" = true ]; then
    echo "Error: --user cannot be combined with stack." >&2
    exit 1
  fi
  if [ "$limit_explicit" = true ]; then
    echo "Error: --limit cannot be combined with stack (a stack prints in full)." >&2
    exit 1
  fi
  if [ "$show_all" = true ]; then
    echo "Error: --all cannot be combined with stack (a stack prints in full)." >&2
    exit 1
  fi
fi

if [ ${#users[@]} -gt 1 ] && [ ${#numbers[@]} -gt 0 ]; then
  echo "Error: cannot combine multiple --user with specific numbers." >&2
  exit 1
fi

if [ "$user_explicit" = true ] && [ ${#numbers[@]} -gt 0 ]; then
  for arg in "${numbers[@]}"; do
    if parse_spec "$arg"; then
      echo "Error: cannot combine --user with item specs." >&2
      exit 1
    fi
  done
fi

# ── CWD repo guard ───────────────────────────────────────────────────
# Only bare numbers and list mode read the current directory's repo;
# fully-qualified specs do not, so `gh-clippy pr django:pr:1` works from
# anywhere, including ~/workspace itself.
needs_cwd_repo=true
if [ "$subcommand" = "stack" ]; then
  # Piped stack JSON names its own repo; self-fetch validates separately.
  needs_cwd_repo=false
elif [ ${#numbers[@]} -gt 0 ]; then
  needs_cwd_repo=false
  for arg in "${numbers[@]}"; do
    if ! parse_spec "$arg"; then
      needs_cwd_repo=true
      break
    fi
  done
fi

if [ "$needs_cwd_repo" = true ] && ! gh repo view --json name >/dev/null 2>&1; then
  echo "Error: not in a GitHub repository. Run this from inside a repo." >&2
  exit 1
fi

# Resolve @me to actual GitHub username
resolve_user() {
  local user="$1"
  if [ "$user" = "@me" ]; then
    gh api user --jq '.login'
  else
    echo "$user"
  fi
}

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
  header_terminal="${ICON_TECHNOLOGIST} "$(printf '%s for \033]8;;%s\033\\@%s\033]8;;\033\\' "$label" "$profile_url" "$user")
}

# Echo one kind-tagged JSON object for a bare number or a repo spec.
fetch_item() {
  local arg="$1"

  if parse_spec "$arg"; then
    local dir="${WORKSPACE_ROOT}/${spec_dir}"
    if [ ! -d "$dir" ]; then
      echo "Error: no such repo directory: $dir" >&2
      exit 1
    fi

    local fields
    if [ "$spec_type" = "pr" ]; then
      fields="$PR_JSON_FIELDS"
    else
      fields="$ISSUE_JSON_FIELDS"
    fi

    local item gh_err_file
    gh_err_file=$(mktemp)
    if ! item=$(cd "$dir" && gh "$spec_type" view "$spec_num" --json "$fields" 2>"$gh_err_file"); then
      if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        echo "Error: not a GitHub repository: $dir" >&2
      else
        echo "Error: could not fetch ${spec_type} #${spec_num} in ${dir}" >&2
        if [ -s "$gh_err_file" ]; then
          cat "$gh_err_file" >&2
        fi
      fi
      rm -f "$gh_err_file"
      exit 1
    fi
    rm -f "$gh_err_file"

    echo "$item" | jq --arg kind "$spec_type" '. + {kind: $kind}'
  else
    # Bare number — current directory's repo, subcommand's type.
    gh "$gh_cmd" view "$arg" --json "$json_fields" \
      | jq --arg kind "$subcommand" '. + {kind: $kind}'
  fi
}

# Read `gh stack view --json` (stdin when piped, else self-fetched) and
# hydrate each branch's PR into the same shape list mode produces.
#
# Stack JSON carries only .pr.{number,url,state}; the renderers need the full
# PR_JSON_FIELDS set, so each PR is re-fetched by number. The repo comes from
# .pr.url rather than the cwd — piped JSON may describe any repository.
# Sets: json
fetch_stack_json() {
  local stack_json
  # Test for a pipe specifically, not merely "not a TTY": </dev/null is a
  # character device and a redirected file is a regular file, so both fall
  # through to self-fetch instead of blocking on a read that never returns.
  if [ -p /dev/fd/0 ]; then
    stack_json=$(cat)
    if [ -z "${stack_json//[[:space:]]/}" ]; then
      echo "Error: no JSON on stdin." >&2
      echo "Expected: gh stack view --json | $(basename "$0") stack" >&2
      exit 1
    fi
  else
    local gh_err_file
    gh_err_file=$(mktemp)
    if ! stack_json=$(gh stack view --json 2>"$gh_err_file"); then
      echo "Error: could not read the current stack." >&2
      if [ -s "$gh_err_file" ]; then
        cat "$gh_err_file" >&2
      fi
      echo "Run this from a branch in a stack, or pipe 'gh stack view --json' in." >&2
      rm -f "$gh_err_file"
      exit 1
    fi
    rm -f "$gh_err_file"
  fi

  if ! echo "$stack_json" | jq -e 'type == "object" and has("branches")' >/dev/null 2>&1; then
    echo "Error: input is not 'gh stack view --json' output." >&2
    exit 1
  fi

  # Branches added locally but never submitted have no PR to render.
  local skipped
  skipped=$(echo "$stack_json" | jq -r '[.branches[] | select(.pr == null) | .name] | join(", ")')
  if [ -n "$skipped" ]; then
    local count
    count=$(echo "$stack_json" | jq '[.branches[] | select(.pr == null)] | length')
    echo "Note: ${count} branch(es) without a PR skipped (${skipped})" >&2
  fi

  local refs
  refs=$(echo "$stack_json" | jq -r '.branches[] | select(.pr != null) | .pr.url')
  if [ -z "$refs" ]; then
    echo "Error: no PRs in this stack yet." >&2
    exit 1
  fi

  # Stack order is the dependency chain, so it is preserved as given.
  json="["
  local first=true url repo num item
  while IFS= read -r url; do
    [ -z "$url" ] && continue
    # https://github.com/<owner>/<repo>/pull/<n>
    repo=$(echo "$url" | sed -E 's#^https?://[^/]+/([^/]+/[^/]+)/pull/[0-9]+.*$#\1#')
    num=$(echo "$url" | sed -E 's#^.*/pull/([0-9]+).*$#\1#')
    if [ "$repo" = "$url" ] || [ "$num" = "$url" ]; then
      echo "Error: could not parse PR URL: $url" >&2
      exit 1
    fi
    local pr_err_file
    pr_err_file=$(mktemp)
    if ! item=$(gh pr view "$num" --repo "$repo" --json "$PR_JSON_FIELDS" 2>"$pr_err_file"); then
      echo "Error: could not fetch PR #${num} in ${repo}" >&2
      if [ -s "$pr_err_file" ]; then
        cat "$pr_err_file" >&2
      fi
      rm -f "$pr_err_file"
      exit 1
    fi
    rm -f "$pr_err_file"
    if [ "$first" = true ]; then first=false; else json+=","; fi
    json+=$(echo "$item" | jq '. + {kind: "pr"}')
  done <<< "$refs"
  json+="]"
}

# Fetch JSON for the current gh_list_filter, numbers, show_all, and limit settings.
# Sets: json
fetch_json() {
  if [ "$subcommand" = "stack" ]; then
    fetch_stack_json
  elif [ ${#numbers[@]} -gt 0 ]; then
    json="["
    local first=true
    for arg in "${numbers[@]}"; do
      local item_json
      item_json=$(fetch_item "$arg")
      if [ "$first" = true ]; then first=false; else json+=","; fi
      json+="$item_json"
    done
    json+="]"
  elif [ "$show_all" = true ]; then
    json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit 100 --state all --json "$json_fields" \
      | jq --arg kind "$subcommand" '[.[] | . + {kind: $kind}]')
  else
    json=$(gh "$gh_cmd" list "${gh_list_filter[@]}" --limit "$limit" --state open --json "$json_fields")
    if [ "$subcommand" = "pr" ]; then
      json=$(echo "$json" | jq '[.[] | select(.isDraft | not)]')
    fi
    json=$(echo "$json" | jq --arg kind "$subcommand" '[.[] | . + {kind: $kind}]')
  fi
}

# Format JSON into html, slack_plain, and terminal_plain.
# Requires: json, JQ_SLACK_EMOJI, JQ_TERMINAL_ICON
# Sets: html, slack_plain, terminal_plain
format_output() {
  html=$(echo "$json" | jq -r "[${JQ_ORDER} | ${JQ_SLICE} | .[] | ${JQ_SLACK_EMOJI} | (.title | gsub(\"<\";\"&lt;\") | gsub(\">\";\"&gt;\")) as \$safe_title | \"\(\$emoji) \(\$safe_title) <a href=\\\"\(.url)\\\">#\(.number)</a>\"] | join(\"<br>\")")
  slack_plain=$(echo "$json" | jq -r "${JQ_ORDER} | ${JQ_SLICE} | .[] | ${JQ_SLACK_EMOJI} | \"\(\$emoji) \(.title) #\(.number)\"")
  terminal_plain=$(echo "$json" | jq -r \
    --arg icon_merged "$ICON_PR_MERGED" \
    --arg icon_closed "$ICON_PR_CLOSED" \
    --arg icon_draft "$ICON_PR_DRAFT" \
    --arg icon_approved "$ICON_PR_APPROVED" \
    --arg icon_changes "$ICON_PR_CHANGES" \
    --arg icon_ready "$ICON_PR_READY" \
    --arg icon_issue_open "$ICON_ISSUE_OPEN" \
    --arg icon_issue_closed "$ICON_ISSUE_CLOSED" \
    "${JQ_ORDER} | ${JQ_SLICE} | .[] | ${JQ_TERMINAL_ICON} | \"\(\$icon) \(.title) \u001b]8;;\(.url)\u001b\\\\#\(.number)\u001b]8;;\u001b\\\\\"")
}

# Format JSON into an HTML table (Link | Status | Title) for MS Teams.
# Requires: json, JQ_TEAMS_STATUS
# Sets: teams_html, teams_plain
format_teams_output() {
  local rows_html rows_plain
  rows_html=$(echo "$json" | jq -r "${JQ_ORDER} | ${JQ_SLICE} | .[] | ${JQ_TEAMS_STATUS} | (.title | gsub(\"<\";\"&lt;\") | gsub(\">\";\"&gt;\")) as \$safe_title | \"<tr><td><a href=\\\"\(.url)\\\">#\(.number)</a></td><td>\(\$status)</td><td>\(\$safe_title)</td></tr>\"" | tr -d '\n')
  teams_html="<table border=\"1\" cellpadding=\"4\" cellspacing=\"0\"><tr><th>Link</th><th>Status</th><th>Title</th></tr>${rows_html}</table>"

  rows_plain=$(echo "$json" | jq -r "${JQ_ORDER} | ${JQ_SLICE} | .[] | ${JQ_TEAMS_STATUS} | \"#\(.number) \(.url)\t\(\$status)\t\(.title)\"")
  teams_plain=$'Link\tStatus\tTitle\n'"${rows_plain}"
}

# ── Output generation ────────────────────────────────────────────────

# ── Ordering and truncation ──────────────────────────────────────────
# Order is never rewritten: explicitly named items follow the order given
# on the command line, and list mode follows the order `gh` returns.
# Explicit items are also never truncated — naming 11 items must print 11.
JQ_ORDER='.'
if [ ${#numbers[@]} -gt 0 ] || [ "$subcommand" = "stack" ]; then
  JQ_SLICE='.'
else
  JQ_SLICE=".[:${limit}]"
fi


# ── Teams table (short-circuit) ───────────────────────────────────────

if [ "$teams" = true ]; then
  if [ "$user_explicit" = true ] && [ ${#users[@]} -gt 1 ]; then
    echo "Error: --teams does not support multiple --user." >&2
    exit 1
  fi

  if [ "$user_explicit" = true ]; then
    if [ "$subcommand" = "pr" ]; then
      gh_list_filter=(--author "${users[0]}")
    else
      gh_list_filter=(--assignee "${users[0]}")
    fi
  fi

  fetch_json
  format_teams_output

  export CLIPBOARD_HTML="$teams_html"
  export CLIPBOARD_PLAIN="$teams_plain"
  swift -e '
import AppKit
let html = ProcessInfo.processInfo.environment["CLIPBOARD_HTML"]!
let plain = ProcessInfo.processInfo.environment["CLIPBOARD_PLAIN"]!
let pb = NSPasteboard.general
pb.clearContents()
pb.setString(html, forType: .html)
pb.setString(plain, forType: .string)
'

  printf '%s\n' "$teams_plain"
  echo ""
  echo "Copied to clipboard — paste into MS Teams for a formatted table"
  exit 0
fi

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

    fetch_json

    # Build header (resolve @me to real username for display/links)
    resolved_user=$(resolve_user "$user")
    build_user_header "$resolved_user"

    format_output

    # Prepend header
    html="${header_html}<br>${html}"
    slack_plain="${header_plain}"$'\n'"${slack_plain}"
    terminal_plain="${header_terminal}"$'\n'"${terminal_plain}"

    # Accumulate with blank line separator
    if [ -n "$all_html" ]; then
      all_html+="<br><br>"
      all_slack_plain+=$'\n\n'
      all_terminal_plain+=$'\n\n'
    fi
    all_html+="$html"
    all_slack_plain+="$slack_plain"
    all_terminal_plain+="$terminal_plain"
  done

  html="$all_html"
  slack_plain="$all_slack_plain"
  terminal_plain="$all_terminal_plain"
else
  # ── Default path (no --user, same as today) ─────────────────────────
  fetch_json
  format_output
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
