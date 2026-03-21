#!/usr/bin/env bash
# NanoClaw service management (macOS launchd / Linux systemd)
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.nanoclaw.plist"
SVC="gui/$(id -u)/com.nanoclaw"

case "${1:-status}" in
  start)
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl bootstrap "$SVC" "$PLIST" 2>/dev/null || launchctl kickstart -k "$SVC"
    else
      systemctl --user start nanoclaw
    fi
    echo "Service started"
    ;;
  stop)
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl bootout "$SVC" 2>/dev/null || true
    else
      systemctl --user stop nanoclaw
    fi
    echo "Service stopped"
    ;;
  restart)
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl kickstart -k "$SVC"
    else
      systemctl --user restart nanoclaw
    fi
    echo "Service restarted"
    ;;
  status)
    if [[ "$(uname)" == "Darwin" ]]; then
      launchctl print "$SVC" 2>/dev/null | head -5 || echo "Not running"
    else
      systemctl --user status nanoclaw
    fi
    ;;
  *)
    echo "Usage: svc.sh {start|stop|restart|status}"
    exit 1
    ;;
esac
