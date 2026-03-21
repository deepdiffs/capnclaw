#!/usr/bin/env bash
# Clear cached agent-runner source for all groups.
# Fresh source will be copied on next container start.
set -euo pipefail

SESSIONS_DIR="$(dirname "$0")/../data/sessions"
count=0

for dir in "$SESSIONS_DIR"/*/agent-runner-src; do
  [ -d "$dir" ] && rm -rf "$dir" && count=$((count + 1))
done

echo "Cleared $count group(s). Fresh source will be copied on next container start."
