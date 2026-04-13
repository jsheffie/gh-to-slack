#!/usr/bin/env bash
# Create branch-named symlinks for git directories matching a prefix.
# Usage: gh-syms <prefix> [create|list|clean] [--no-strict-nums-only] [--verbose]

set -euo pipefail

VERSION="1.0.7"
RELEASES_URL="https://github.com/jsheffie/gh-to-slack/releases"
README_URL="https://github.com/jsheffie/gh-to-slack"

usage() {
  cat <<EOF
Usage: $(basename "$0") <prefix> [create|list|clean] [--no-strict-nums-only] [--verbose]

Create symlinks of the form <dirname>-<branch> for every real git directory
in the current working directory whose name starts with <prefix>.

By default only directories named exactly <prefix> or <prefix><N> (where N is
a positive integer) are processed — e.g. django, django2, django3 but not
django-old. Pass --no-strict-nums-only to process all <prefix>* directories.

Subcommands:
  (none)    Remove stale symlinks, create fresh ones, then list. (default)
  create    Create/refresh symlinks only (no listing).
  list      List existing symlinks for <prefix> without making changes.
  clean     Remove all symlinks targeting <prefix>* directories.

Options:
  --no-strict-nums-only   Also process directories like django-old, django_bak.
  --verbose               Print each removal and creation (default: list only).
  --version               Show version and exit.
  -h, --help              Show this help message and exit.

Examples:
  $(basename "$0") django
      Removes stale symlinks, creates fresh ones, then lists:
        django   -> django-feature-auth
        django2  -> django2-main

  $(basename "$0") django list
      Lists existing symlinks without making changes.

  $(basename "$0") django clean
      Removes all symlinks targeting django* directories.

  $(basename "$0") django --no-strict-nums-only
      Also processes django-old, django_bak, etc.

  $(basename "$0") django --verbose
      Shows each removal and creation before the final list.
EOF
  exit 0
}

if [ $# -eq 0 ]; then
  echo "Error: prefix argument required." >&2
  echo "Run '$(basename "$0") --help' for usage." >&2
  exit 1
fi

case "$1" in
  -h|--help) usage ;;
  --version)
    printf '\ngh-syms %s\n\n' "${VERSION}"
    printf 'Check \033]8;;%s\033\\gh-to-slack releases\033]8;;\033\\. If you are not on the latest version\nsee \033]8;;%s\033\\README\033]8;;\033\\ for install upgrade instructions\n\n' "${RELEASES_URL}" "${README_URL}"
    exit 0
    ;;
esac

BASE="$1"
shift

SUBCMD="default"
OPT_STRICT=1
OPT_VERBOSE=0

for arg in "$@"; do
  case "$arg" in
    create|list|clean)     SUBCMD="$arg" ;;
    --no-strict-nums-only) OPT_STRICT=0 ;;
    --verbose)             OPT_VERBOSE=1 ;;
    -h|--help)             usage ;;
    *) echo "Error: unknown argument '$arg'." >&2; exit 1 ;;
  esac
done

# Returns 0 if dirname passes the active filter, 1 otherwise.
dir_matches() {
  local d="$1"
  if [ "$OPT_STRICT" -eq 1 ]; then
    # Accept exactly <BASE> or <BASE><digits>
    [[ "$d" =~ ^${BASE}[0-9]*$ ]]
  else
    return 0
  fi
}

# ── clean subcommand ───────────────────────────────────────────────────
if [ "$SUBCMD" = "clean" ]; then
  found=0
  while IFS= read -r -d '' sym; do
    target=$(readlink "$sym")
    if dir_matches "$target"; then
      rm "$sym"
      [ "$OPT_VERBOSE" -eq 1 ] && echo "Removed:  ${sym#./}"
      found=1
    fi
  done < <(find . -maxdepth 1 -type l -print0)
  [ "$found" -eq 0 ] && echo "No symlinks found to remove for prefix '${BASE}'."
  exit 0
fi

# ── list helper (used by list subcommand and default run) ──────────────
do_list() {
  declare -a list_syms list_targets
  local maxlen=0
  while IFS= read -r -d '' sym; do
    local target
    target=$(readlink "$sym")
    if dir_matches "$target"; then
      list_syms+=("${sym#./}")
      list_targets+=("$target")
      [ ${#target} -gt $maxlen ] && maxlen=${#target}
    fi
  done < <(find . -maxdepth 1 -type l -print0 | sort -z)

  if [ ${#list_syms[@]} -eq 0 ]; then
    echo "No symlinks found for prefix '${BASE}'."
    return
  fi

  local pad=$(( maxlen + 1 ))
  for i in "${!list_syms[@]}"; do
    printf "  %-${pad}s -> %s\n" "${list_targets[$i]}" "${list_syms[$i]}"
  done
}

if [ "$SUBCMD" = "list" ]; then
  do_list
  exit 0
fi

# ── create / default: collect matching real directories ────────────────
shopt -s nullglob
dirs=()
for entry in "${BASE}"*/; do
  dir="${entry%/}"
  [ -d "$dir" ] && [ ! -L "$dir" ] || continue
  dir_matches "$dir" || continue
  dirs+=("$dir")
done
shopt -u nullglob

if [ ${#dirs[@]} -eq 0 ]; then
  echo "No directories found matching '${BASE}*' in $(pwd)." >&2
  exit 1
fi

for dirname in "${dirs[@]}"; do
  # Verify it's a git repo
  if ! git -C "$dirname" rev-parse HEAD >/dev/null 2>&1; then
    echo "Warning: '$dirname' is not a git repo — skipping." >&2
    continue
  fi

  # Get current branch; sanitize slashes → dashes
  branch=$(git -C "$dirname" rev-parse --abbrev-ref HEAD | tr '/' '-')
  symname="${dirname}-${branch}"

  # Remove existing symlinks in CWD that target this directory
  while IFS= read -r -d '' existing; do
    target=$(readlink "$existing")
    if [ "$target" = "$dirname" ]; then
      rm "$existing"
      [ "$OPT_VERBOSE" -eq 1 ] && echo "Removed:  ${existing#./}"
    fi
  done < <(find . -maxdepth 1 -type l -print0)

  # Create new symlink
  ln -s "$dirname" "$symname"
  [ "$OPT_VERBOSE" -eq 1 ] && echo "Created:  $symname -> $dirname"
done

# Default run also prints the listing; bare `create` subcommand does not.
if [ "$SUBCMD" = "default" ]; then
  do_list
fi
