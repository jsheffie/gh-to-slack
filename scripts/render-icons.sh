#!/usr/bin/env bash
set -euo pipefail

# Generates colored PNG icons from GitHub Primer Octicons SVGs.
# Dev dependency: brew install librsvg

if ! command -v rsvg-convert &>/dev/null; then
  echo "Error: rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR="${SCRIPT_DIR}/../icons"
mkdir -p "$ICON_DIR"

OCTICONS_BASE="https://raw.githubusercontent.com/primer/octicons/main/icons"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Generate a colored PNG from an Octicon SVG
# Usage: generate_icon <name> <svg-file> <color>
generate_icon() {
  local name="$1" svg_file="$2" color="$3"
  local svg_url="${OCTICONS_BASE}/${svg_file}"

  echo "Generating ${name}.png (${svg_file}, ${color})..."

  curl -fsSL "$svg_url" -o "${TMP_DIR}/${name}.svg"

  # Add fill attribute to the root <svg> element to colorize
  sed -i '' "s/<svg /<svg fill=\"${color}\" /" "${TMP_DIR}/${name}.svg"

  rsvg-convert -w 32 -h 32 "${TMP_DIR}/${name}.svg" -o "${ICON_DIR}/${name}.png"
}

generate_icon "pr-merged"            "git-merge-24.svg"                "#8250df"
generate_icon "pr-closed"            "git-pull-request-closed-24.svg"  "#cf222e"
generate_icon "pr-draft"             "git-pull-request-draft-24.svg"   "#656d76"
generate_icon "pr-approved"          "git-pull-request-24.svg"         "#1a7f37"
generate_icon "pr-changes-requested" "git-pull-request-24.svg"         "#bf8700"
generate_icon "pr-ready-for-review"  "git-pull-request-24.svg"         "#bf8700"
generate_icon "issue-open"           "issue-opened-24.svg"             "#1a7f37"
generate_icon "issue-closed"         "issue-closed-24.svg"             "#8250df"

# Technologist emoji from Twemoji (CC-BY 4.0)
TWEMOJI_URL="https://raw.githubusercontent.com/twitter/twemoji/master/assets/72x72/1f9d1-200d-1f4bb.png"
echo "Generating technologist.png (twemoji)..."
curl -fsSL "$TWEMOJI_URL" -o "${TMP_DIR}/technologist-raw.png"
sips -z 32 32 "${TMP_DIR}/technologist-raw.png" --out "${ICON_DIR}/technologist.png" >/dev/null 2>&1

echo "Done. Icons written to ${ICON_DIR}/"
ls -la "${ICON_DIR}/"
