# QMD centralized sync

Each agent pushes its conversations/docs to the Mac Studio over Tailscale;
a watcher on the studio re-embeds the per-agent qmd collection on change.
Agents query the centralized qmd over HTTP MCP (`QMD_MCP_URL`).

```
┌──────────┐          rsync (ssh)         ┌───────────────────┐
│  agent   │  ─────────────────────────▶ │   Mac Studio      │
│ (capn…)  │   groups/*/conversations    │ /var/qmd/sources/ │
└──────────┘         /docs                │        │         │
      ▲                                   │        ▼         │
      │ HTTP MCP (QMD_MCP_URL)            │  studio-watcher  │
      │ mcp__qmd__query, etc.             │   (fswatch +     │
      └────────────────────────────────── │    qmd embed)    │
                                          └───────────────────┘
```

## Agent side (automatic via deploy.sh)

Add a `qmd` block to `agents/<name>/agent.json`:

```json
{
  "name": "capn",
  "host": "piclaw",
  "path": "/home/jj/workspace/projects/claw",
  "postDeploy": "npm run deploy",
  "qmd": {
    "collection": "capn",
    "sources": [
      "groups/telegram_main/conversations",
      "groups/telegram_main/docs",
      "groups/telegram_main/CLAUDE.md"
    ],
    "intervalSeconds": 300,
    "studio": {
      "host": "studio.raptor-tilapia.ts.net",
      "user": "j",
      "root": "/var/qmd/sources"
    }
  }
}
```

`deploy.sh <name>` then:

1. Writes `<path>/.qmd-sync.json` on the target (the qmd block verbatim).
2. Runs `scripts/qmd/install-agent-sync.sh` on the target to install a
   launchd agent (macOS) or `systemd --user` timer (linux) that calls
   `sync-to-studio.sh` every `intervalSeconds`.

Re-running deploy is idempotent — the unit is replaced and reloaded.

### Requirements on the agent host

- `jq` installed (`apt install jq` / `brew install jq`)
- SSH access to the studio using the deploying user's identity
  (Tailscale SSH or `~/.ssh/authorized_keys` — whichever you use)
- On linux, `loginctl enable-linger <user>` is attempted automatically
  so user-scope systemd units survive logout

### Logs on the agent host

- `<path>/logs/qmd-sync.log` — stdout from each sync run
- `<path>/logs/qmd-sync.err` — stderr

On linux: `journalctl --user -u nanoclaw-qmdsync.service -f` also works.

## Studio side (one-time manual setup)

On the Mac Studio:

1. **Install prerequisites**
   ```bash
   brew install fswatch jq
   # qmd itself should already be installed and running as the centralized MCP.
   ```

2. **Create the sources root**
   ```bash
   sudo mkdir -p /var/qmd/sources
   sudo chown "$USER" /var/qmd/sources
   ```

3. **Allow SSH from each agent's Tailscale identity**

   Either enable Tailscale SSH for the studio (`tailscale up --ssh`) and
   grant the relevant tag in your ACLs, or add each agent's public key to
   `~/.ssh/authorized_keys`. Test from an agent:
   ```bash
   ssh studio.raptor-tilapia.ts.net "echo ok"
   ```

4. **Copy `studio-watcher.sh` somewhere permanent**
   ```bash
   mkdir -p ~/bin
   cp /path/to/capnclaw/scripts/qmd/studio-watcher.sh ~/bin/
   chmod +x ~/bin/studio-watcher.sh
   ```

5. **Install the watcher as a launchd agent**

   Create `~/Library/LaunchAgents/com.nanoclaw.qmd-watcher.plist`:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>Label</key><string>com.nanoclaw.qmd-watcher</string>
     <key>ProgramArguments</key>
     <array>
       <string>/bin/bash</string>
       <string>/Users/YOU/bin/studio-watcher.sh</string>
     </array>
     <key>RunAtLoad</key><true/>
     <key>KeepAlive</key><true/>
     <key>StandardOutPath</key><string>/tmp/qmd-watcher.log</string>
     <key>StandardErrorPath</key><string>/tmp/qmd-watcher.err</string>
     <key>EnvironmentVariables</key>
     <dict>
       <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
       <key>QMD_SOURCES_ROOT</key><string>/var/qmd/sources</string>
     </dict>
   </dict>
   </plist>
   ```

   Then load:
   ```bash
   launchctl load -w ~/Library/LaunchAgents/com.nanoclaw.qmd-watcher.plist
   tail -f /tmp/qmd-watcher.log
   ```

6. **End-to-end verification**

   From your dev machine:
   ```bash
   ./deploy.sh capn                 # installs sync unit on piclaw
   ssh piclaw "bash /home/jj/workspace/projects/claw/scripts/qmd/sync-to-studio.sh"
   ```
   Within ~10 seconds you should see `reindexing capn` in
   `/tmp/qmd-watcher.log` on the studio, and `mcp__qmd__status` from a
   container agent should show `capn` with a non-zero doc count.

## Adjusting the qmd CLI calls

The watcher calls `qmd collection add <name> --path <dir>` and
`qmd embed <name>`. If your qmd version uses different subcommands, set
`QMD_ADD_CMD` / `QMD_EMBED_CMD` in the launchd plist, e.g.:

```xml
<key>QMD_ADD_CMD</key><string>qmd index add</string>
<key>QMD_EMBED_CMD</key><string>qmd index embed</string>
```

No code edits required.

## Uninstall

Agent host (macOS):
```bash
launchctl unload -w ~/Library/LaunchAgents/com.nanoclaw.qmdsync.plist
rm ~/Library/LaunchAgents/com.nanoclaw.qmdsync.plist
```

Agent host (linux):
```bash
systemctl --user disable --now nanoclaw-qmdsync.timer
rm ~/.config/systemd/user/nanoclaw-qmdsync.{service,timer}
systemctl --user daemon-reload
```

Studio:
```bash
launchctl unload -w ~/Library/LaunchAgents/com.nanoclaw.qmd-watcher.plist
rm ~/Library/LaunchAgents/com.nanoclaw.qmd-watcher.plist
```
