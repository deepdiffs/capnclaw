#!/usr/bin/env bash
# ============================================================================
# qmd studio-side watcher — runs on the Mac Studio (or wherever qmd lives)
# ============================================================================
#
# Watches $QMD_SOURCES_ROOT for changes and re-embeds the touched collection.
# Debounces rapid filesystem events (e.g. a multi-file rsync from an agent)
# into one embed call per collection per debounce window.
#
# Directory layout assumed:
#   $QMD_SOURCES_ROOT/<collection>/<agent source tree>
#
# Each top-level directory under QMD_SOURCES_ROOT is a qmd collection.
# When files under collection X change, the watcher runs:
#   $QMD_ADD_CMD X $QMD_SOURCES_ROOT/X
#   $QMD_EMBED_CMD X
#
# The exact add/embed commands vary between qmd versions, so they're
# parameterized via environment variables. Defaults match recent qmd;
# override in the launchd plist if your CLI uses different flags.
#
# Env:
#   QMD_SOURCES_ROOT  default: /var/qmd/sources
#   QMD_DEBOUNCE      default: 10 (seconds to coalesce events)
#   QMD_STATE_DIR     default: /tmp/qmd-watcher
#   QMD_ADD_CMD       default: "qmd collection add"
#   QMD_EMBED_CMD     default: "qmd embed"
# ============================================================================
set -euo pipefail

SOURCES_ROOT="${QMD_SOURCES_ROOT:-/var/qmd/sources}"
DEBOUNCE_SECONDS="${QMD_DEBOUNCE:-10}"
STATE_DIR="${QMD_STATE_DIR:-/tmp/qmd-watcher}"
ADD_CMD="${QMD_ADD_CMD:-qmd collection add}"
EMBED_CMD="${QMD_EMBED_CMD:-qmd embed}"

mkdir -p "$STATE_DIR" "$SOURCES_ROOT"

if ! command -v fswatch >/dev/null 2>&1; then
  echo "studio-watcher: fswatch required (brew install fswatch)" >&2
  exit 1
fi
if ! command -v qmd >/dev/null 2>&1; then
  echo "studio-watcher: qmd required in PATH" >&2
  exit 1
fi

log() { echo "[$(date -Iseconds 2>/dev/null || date +%FT%T%z)] $*"; }

log "watching $SOURCES_ROOT (debounce ${DEBOUNCE_SECONDS}s)"

# Writer: mark a collection dirty whenever anything under it changes.
# fswatch prints one path per event; we derive the collection from the
# first path segment relative to SOURCES_ROOT.
(
  fswatch -r --latency 1 "$SOURCES_ROOT" | while read -r path; do
    rel="${path#"$SOURCES_ROOT"/}"
    collection="${rel%%/*}"
    # Skip events on the root itself or anything without a collection prefix.
    [[ -z "$collection" || "$collection" == "$rel" ]] && continue
    touch "$STATE_DIR/dirty-$collection"
  done
) &
WRITER_PID=$!
trap 'kill $WRITER_PID 2>/dev/null || true' EXIT

# Reader: every DEBOUNCE_SECONDS, reindex any collection with a dirty marker.
while sleep "$DEBOUNCE_SECONDS"; do
  shopt -s nullglob
  markers=("$STATE_DIR"/dirty-*)
  shopt -u nullglob
  for marker in "${markers[@]}"; do
    collection=$(basename "$marker" | sed 's/^dirty-//')
    rm -f "$marker"
    src="$SOURCES_ROOT/$collection"
    if [[ ! -d "$src" ]]; then
      log "skip $collection (no directory at $src)"
      continue
    fi
    log "reindexing $collection"
    # Best-effort: ensure collection exists, then embed. Errors are logged
    # but do not stop the loop — we'd rather miss one reindex than exit.
    # qmd resolves collection paths relative to cwd, so we cd into the
    # sources root so `qmd collection add capn` maps to $SOURCES_ROOT/capn.
    if ! (cd "$SOURCES_ROOT" && $ADD_CMD "$collection") >/dev/null 2>&1; then
      # add may fail if the collection already exists — that's fine.
      :
    fi
    if ! $EMBED_CMD "$collection"; then
      log "  embed failed for $collection"
    fi
  done
done
