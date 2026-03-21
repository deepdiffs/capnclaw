#!/usr/bin/env bash
# Test the agent container by piping a prompt
set -euo pipefail

PROMPT="${1:-Say hello}"
echo "{\"prompt\":\"$PROMPT\",\"groupFolder\":\"test\",\"chatJid\":\"test@g.us\",\"isMain\":false}" \
  | docker run -i --rm nanoclaw-agent:latest
