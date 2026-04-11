# Multi-Agent Deployment Plan

Run 4-8 NanoClaw agents on different machines, all sharing the same core codebase but with different personalities, credentials, conversation history, and goals. Deploy all from one machine.

## Architecture: Overlay Directories + Deploy Script

### Shared Code (same across all agents)

- `src/` — orchestrator, channels, container runner
- `container/` — Dockerfile, agent-runner, skills
- `package.json`, `tsconfig.json`, build scripts
- `CLAUDE.md` (framework docs), `CONTRIBUTING.md`

### Instance-Specific (different per agent)

- `groups/` — personality CLAUDE.md files, conversation history
- `store/messages.db` — message history, registered groups, sessions
- `data/sessions/` — Claude Code session state per group
- `.env` — credentials, `ASSISTANT_NAME`, bot tokens
- `launchd/com.nanoclaw.plist` — service config
- `logs/` — runtime logs

### Directory Structure

```
capnclaw/
  src/                          # shared core
  container/                    # shared core
  package.json                  # shared core
  agents/                       # per-agent overlays
    miniclaw/                   # current agent (first)
      agent.json                # target host, deploy config
      .env                      # credentials, ASSISTANT_NAME
      groups/
        global/CLAUDE.md        # personality template
        telegram_main/CLAUDE.md # main group personality
    sage/                       # example second agent
      agent.json
      .env
      groups/
        global/CLAUDE.md
        telegram_main/CLAUDE.md
  deploy.sh                     # deploys agent to target
```

### `agent.json` Schema

```json
{
  "name": "miniclaw",
  "host": "user@hostname",
  "path": "/home/user/nanoclaw",
  "postDeploy": "npm run deploy"
}
```

### Deploy Script Behavior

```bash
./deploy.sh miniclaw        # deploy one agent to its target machine
./deploy.sh --all           # deploy all agents
./deploy.sh --all --code    # core code only (skip .env/personality)
```

The script:
1. rsyncs core code (excluding `agents/`, `store/`, `data/`, `logs/`, `node_modules/`, `dist/`) to `host:path`
2. rsyncs the agent's overlay on top (overwrites personality files, drops in `.env`)
3. Runs `postDeploy` command on target (build + restart)

### Instance Data Lifecycle

On each target machine, these are created fresh and stay local (never rsynced):
- `store/` — SQLite DB, created on first run
- `data/` — session state, created on first container spawn
- `logs/` — runtime logs, created by service manager

A redeploy never touches these. The agent keeps all history intact.

### First-Time Setup on New Machine

1. `deploy.sh <agent-name>` — pushes core + overlay
2. Remote: `npm install && npm run build && npm run container:build`
3. Remote: run `/setup` for first-time channel auth + group registration
4. First message triggers DB creation, group registration, sessions

### Ongoing Sync

- Code change: `./deploy.sh --all` pushes everywhere
- Single agent personality change: `./deploy.sh miniclaw`
- Instance data never conflicts (all gitignored)

### Implementation Steps

1. Create `agents/` directory structure
2. Extract current miniclaw config as first agent overlay
3. Write `deploy.sh` (rsync core + overlay, remote build/restart)
4. Gitignore `agents/*/.env` but track everything else
5. Verify current agent still works after restructure
6. Add second agent overlay, deploy to new machine
