#!/usr/bin/env bash
# ============================================================================
# qmd push-sync — agent host → Mac Studio
# ============================================================================
#
# Reads the qmd block from `<nanoclaw-root>/.qmd-sync.json` (written onto the
# target by deploy.sh) and rsyncs the configured source paths to the
# centralized qmd host over Tailscale SSH. Runs periodically via launchd
# (macOS) or systemd --user (linux).
#
#   Usage: sync-to-studio.sh [<nanoclaw-root>]
#
# The studio-side watcher (studio-watcher.sh) picks up the incoming files
# and re-embeds the matching qmd collection. This script only moves bytes.
# ============================================================================
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
CONFIG="$ROOT/.qmd-sync.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "qmd-sync: no $CONFIG (qmd sync not configured for this agent)"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "qmd-sync: jq is required but not installed" >&2
  exit 1
fi

COLLECTION=$(jq -r '.collection' "$CONFIG")
STUDIO_HOST=$(jq -r '.studio.host // "studio.raptor-tilapia.ts.net"' "$CONFIG")
STUDIO_USER=$(jq -r '.studio.user // empty' "$CONFIG")
STUDIO_ROOT=$(jq -r '.studio.root // "/var/qmd/sources"' "$CONFIG")

if [[ -z "$COLLECTION" || "$COLLECTION" == "null" ]]; then
  echo "qmd-sync: .collection is required in $CONFIG" >&2
  exit 1
fi

SSH_SPEC="${STUDIO_USER:+${STUDIO_USER}@}${STUDIO_HOST}"
DEST="${SSH_SPEC}:${STUDIO_ROOT}/${COLLECTION}/"

# Collect source paths. Each entry is a path relative to $ROOT.
# We cd into ROOT and pass relative paths with rsync -R so the tree
# structure is preserved under the destination without leaking the
# absolute path of the agent host.
cd "$ROOT"

args=()
while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  if [[ ! -e "$src" ]]; then
    echo "qmd-sync: skip $src (not present on this host)"
    continue
  fi
  args+=("$src")
done < <(jq -r '.sources[]?' "$CONFIG")

if [[ ${#args[@]} -eq 0 ]]; then
  echo "qmd-sync: no source paths present — nothing to sync"
  exit 0
fi

# Ensure remote collection directory exists (mkdir -p is a no-op if present).
ssh -o ConnectTimeout=10 "$SSH_SPEC" \
  "mkdir -p $(printf '%q' "${STUDIO_ROOT}/${COLLECTION}")"

echo "qmd-sync: pushing collection '$COLLECTION' → $DEST"
# -R (--relative) preserves path structure under the destination.
# No --delete: accidental deletion of indexed content is worse than staleness;
# run `qmd` manually on the studio if you need to prune.
rsync -azR "${args[@]}" "$DEST"
echo "qmd-sync: done"
