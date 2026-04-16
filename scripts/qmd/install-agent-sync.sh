#!/usr/bin/env bash
# ============================================================================
# Install periodic qmd-sync unit on the agent host
# ============================================================================
#
# Installs a user-scope timer that invokes sync-to-studio.sh every N seconds:
#   macOS → launchd agent at ~/Library/LaunchAgents/com.nanoclaw.qmdsync.plist
#   linux → systemd --user timer at ~/.config/systemd/user/nanoclaw-qmdsync.*
#
# Idempotent: re-running overwrites the existing unit and reloads it.
#
#   Usage: install-agent-sync.sh <nanoclaw-root> [<interval-seconds>]
#
# Run from deploy.sh on the target (or locally for a localhost agent) after
# .qmd-sync.json has been written into <nanoclaw-root>.
# ============================================================================
set -euo pipefail

ROOT="${1:-}"
INTERVAL="${2:-300}"

if [[ -z "$ROOT" ]]; then
  echo "Usage: install-agent-sync.sh <nanoclaw-root> [<interval-seconds>]" >&2
  exit 1
fi

if [[ ! -f "$ROOT/scripts/qmd/sync-to-studio.sh" ]]; then
  echo "install-agent-sync: $ROOT/scripts/qmd/sync-to-studio.sh not found" >&2
  exit 1
fi

mkdir -p "$ROOT/logs"

UNAME=$(uname -s)
case "$UNAME" in
  Darwin)
    LABEL="com.nanoclaw.qmdsync"
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/scripts/qmd/sync-to-studio.sh</string>
    <string>${ROOT}</string>
  </array>
  <key>StartInterval</key><integer>${INTERVAL}</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>${ROOT}/logs/qmd-sync.log</string>
  <key>StandardErrorPath</key><string>${ROOT}/logs/qmd-sync.err</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" >/dev/null 2>&1 || true
    launchctl load -w "$PLIST"
    echo "install-agent-sync: launchd unit ${LABEL} installed (every ${INTERVAL}s)"
    ;;

  Linux)
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_DIR/nanoclaw-qmdsync.service" <<EOF
[Unit]
Description=NanoClaw qmd push-sync to centralized studio

[Service]
Type=oneshot
ExecStart=/bin/bash ${ROOT}/scripts/qmd/sync-to-studio.sh ${ROOT}
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
StandardOutput=append:${ROOT}/logs/qmd-sync.log
StandardError=append:${ROOT}/logs/qmd-sync.err
EOF
    cat > "$UNIT_DIR/nanoclaw-qmdsync.timer" <<EOF
[Unit]
Description=Periodic NanoClaw qmd push-sync

[Timer]
OnBootSec=60
OnUnitActiveSec=${INTERVAL}
Unit=nanoclaw-qmdsync.service

[Install]
WantedBy=timers.target
EOF
    # User-scope units die at logout unless linger is enabled.
    if command -v loginctl >/dev/null 2>&1; then
      loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    fi
    systemctl --user daemon-reload
    systemctl --user enable --now nanoclaw-qmdsync.timer
    echo "install-agent-sync: systemd --user timer installed (every ${INTERVAL}s)"
    ;;

  *)
    echo "install-agent-sync: unsupported OS '$UNAME'" >&2
    exit 1
    ;;
esac
