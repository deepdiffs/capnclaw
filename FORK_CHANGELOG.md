# Fork Changelog

Changes made in this fork that differ from upstream NanoClaw.

## 2026-04-14

### Added
- **Automatic qmd push-sync from each agent to the centralized studio**: Each `agents/<name>/agent.json` now takes an optional `qmd` block (`collection`, `sources`, `intervalSeconds`, `studio: {host,user,root}`). When present, `deploy.sh` writes the block verbatim as `<path>/.qmd-sync.json` on the target and runs `scripts/qmd/install-agent-sync.sh` to install a launchd agent (macOS) or `systemd --user` timer (linux) that invokes `scripts/qmd/sync-to-studio.sh` every `intervalSeconds`. The sync is a plain rsync-over-SSH push of the listed source paths (conversations, docs, CLAUDE.md) into `/var/qmd/sources/<collection>/` on `studio.raptor-tilapia.ts.net`. Idempotent — re-running deploy replaces and reloads the unit. Adding a new agent is now just `agent.json` + `deploy.sh`. Wired `qmd` blocks into `capn`, `miniclaw`, and `sage` (each targeting a collection named after the agent)
- **Studio-side qmd watcher (`scripts/qmd/studio-watcher.sh`)**: Runs on the Mac Studio, uses `fswatch -r` on `/var/qmd/sources/`, derives the collection from the first path segment under that root, debounces rapid events (default 10s coalesce window) into one re-embed per collection, then calls `qmd collection add <name> --path <dir>` + `qmd embed <name>`. CLI commands are parameterized via `QMD_ADD_CMD` / `QMD_EMBED_CMD` env vars so different qmd versions can plug in without editing the script. Ships with a launchd plist template in `scripts/qmd/README.md` for the studio operator to install once
- **`scripts/qmd/README.md`**: Architecture diagram, agent.json schema example, one-time studio setup steps (fswatch/jq install, sources-root permissions, Tailscale SSH, launchd plist, end-to-end verification), and uninstall instructions
- **deploy.sh `install_qmd_sync` helper**: Reads `.qmd` from agent.json via `jq`, generates the on-target config from a `mktemp` scratch file, routes to `install -m 644` locally or `rsync` + `ssh` remotely. Called from both the localhost and remote branches of `deploy_agent` after overlay sync and before postDeploy. Added `--exclude='.qmd-sync.json'` to `CORE_EXCLUDES` so a dev-machine copy can never get pushed as code, and added `.qmd-sync.json` to `.gitignore`. Added invariant #8 to the header comment documenting the qmd sync layer

## 2026-04-13

### Changed
- **Disabled WebSearch tool in agent runner**: Added `disallowedTools: ['WebSearch']` to the Claude Agent SDK query options in `container/agent-runner/src/index.ts`. Agents should reach for Parallel AI search MCP instead, which is routed through OneCLI and returns structured results
- **Tightened Telegram formatting guidance in `groups/telegram_main/CLAUDE.md`**: Replaced the verbose MTProto `messageEntity*` TL schema dump with a short, actionable rule — use plain Telegram Markdown (not MarkdownV2), do NOT escape `.` `-` `!` `(` `)` `_` with backslashes. The old schema reference was confusing the model into emitting MarkdownV2-style escapes that rendered as literal `\` in chat

## 2026-04-12

### Added
- **Centralized QMD MCP over Tailscale**: Agents now point at a single shared qmd instance on a homelab Mac Studio (reached via a tailnet MagicDNS name) instead of running a per-host qmd daemon. `container-runner.ts` forwards `QMD_MCP_URL` from `.env` to the container, and `container/agent-runner/src/index.ts` registers it as an HTTP MCP server at session start (with an explicit log line naming the URL for diagnostics). No host-local fallback — if `QMD_MCP_URL` is unset, qmd is simply not registered. Motivation: one qmd, one index, one ~1.6GB model cache serving capn/miniclaw/sage instead of each machine carrying its own
- **NO_PROXY bypass for the QMD MCP host**: Node's undici `EnvHttpProxyAgent` (still marked experimental) fails to parse OneCLI's proxy response when forwarding to private tailnet destinations, with `"Response does not match the HTTP/1.1 protocol"` — even though curl through the same proxy works fine and OneCLI's forwarding is correct. Fix: at the top of the agent-runner module, parse `QMD_MCP_URL`, extract its hostname, and append it to `NO_PROXY`/`no_proxy` before the SDK constructs its HTTP agents. Node's fetch then connects directly via the container's tailnet routing (verified working via `docker exec … curl --noproxy '*'`), while all other traffic stays on the OneCLI-managed proxy path
- **Rewrote `container/skills/qmd/SKILL.md`** to reflect the centralized architecture: removed host-only `npx qmd` CLI fallback (unreachable from containers once qmd moves off-host) and instructed the agent to call `mcp__qmd__status` to discover collections instead of hardcoding `telegram_main`. Kept the grep-over-mounted-conversations fallback as last resort

### Fixed
- **Parallel AI MCP servers broken after OneCLI migration**: The OneCLI migration (`f8a6437`) removed the `-e PARALLEL_API_KEY=…` env injection from `container-runner.ts`, so `process.env.PARALLEL_API_KEY` was always undefined inside containers and the `parallel-search` / `parallel-task` MCP servers were silently skipped. The existing vault secret also had host-pattern `api.parallel.ai`, which didn't match the MCP subdomains. Fix: added two new OneCLI secrets ("Parallel Search MCP", "Parallel Task MCP") with host-patterns `search-mcp.parallel.ai` and `task-mcp.parallel.ai` and `Authorization: Bearer {value}` injection; updated `container/agent-runner/src/index.ts` to unconditionally register the Parallel MCP servers without an `Authorization` header (OneCLI injects it at the proxy layer). Containers still never see the raw `PARALLEL_API_KEY`

## 2026-04-11

### Added
- Multi-agent deployment infrastructure (`agents/` directory, `deploy.sh`)
- Agent overlay pattern: per-agent `agent.json`, `.env`, and `groups/` personality files
- `miniclaw` as first agent overlay (extracted from current config)
- `sage` as example second agent overlay
- Deploy script supports single agent, `--all`, and `--code` (code-only) modes
- `capn` agent overlay for piclaw (first remote deployment target)

### Changed
- Migrated from native credential proxy to OneCLI Agent Vault — both local and remote agents use the same credential system. Anthropic, Parallel AI, and Whisper keys moved from `.env` to vault

- **Removed reviewer group**: Cleaned up `telegram_the-reviewer` group directory and database registration entry from previous setup attempt
- **Docker .env shadow mount**: Restored explicit `/dev/null` mount over `.env` in container-runner for Docker runtime (Apple Container uses entrypoint mount-bind instead). Improves defense-in-depth for secret isolation
- **Multi-agent deployment plan**: Added `docs/multi-agent-plan.md` — architecture for running 4-8 agents from the same codebase using overlay directories and a deploy script
- **Upstream merge (v1.2.42 → v1.2.52)**: Merged upstream/main + 5 skill branches. Key upstream changes: Agent SDK 0.2.92 (1M context, 200k auto-compact), auto-compact threshold 165k tokens, session cleanup (stale artifact pruning), stale session recovery, reply/quoted message context, writable global memory mount, store mounted rw for main agent, npm audit fixes. Resolved 4 conflicts in upstream/main merge — kept our tool logging hooks, AskUserQuestion, Parallel AI MCP tools, credential proxy, and `telegram_main` group folder
- **Skill updates**: Updated apple-container (22 commits — entrypoint privilege dropping, .env mount-bind shadowing), compact (19 commits — `/compact` session command with slash-command handling in host and container), channel-formatting (3 commits — text-styles.ts for channel-native formatting), ollama-tool (3 commits — admin tools flag, updated MCP config). Installed new qmd skill (QMD MCP server at `host.docker.internal:8182`). Wiki already up to date
- **Docker runtime fix**: Restored `src/container-runtime.ts` to Docker after apple-container merge overwrote it with Apple Container code (duplicate `CONTAINER_HOST_GATEWAY`/`PROXY_BIND_HOST` declarations). Updated tests to match Docker runtime commands
- **Diagnostics opt-out**: Permanently opted out of NanoClaw telemetry — replaced diagnostics.md files with opt-out markers, removed diagnostics sections from SKILL.md files
- **Removed weekly-review planning docs** — deleted implementation plan and design spec from `docs/superpowers/` now that the skill has been implemented and simplified
- **deploy.sh documentation header**: Captured the multi-agent architecture, deploy flow, and hard-won invariants (overlay `.env` authoritative/no-merge, per-machine `ONECLI_URL`, OneCLI vault for creds, unique Telegram bot per agent, `groups/global/***` include rule) plus subtle pitfalls (show_diff stdin gotcha, rsync include/exclude ordering) at the top of `deploy.sh` for future reference

## 2026-03-29

- **Added weekly-review container skill** — guided personal weekly review via adaptive Q&A in isolated context, with scoring, trends, and next-week planning
- **Added AskUserQuestion to container allowed tools** — enables structured Q&A prompts in container skills

## 2026-03-28

- **Telegram voice transcription**: Added `src/transcription.ts` module that sends voice audio to an OpenAI-compatible Whisper endpoint for transcription. Modified Telegram voice handler to download voice files, transcribe them, and store `[Voice: transcript]` instead of `[Voice message]` placeholder. Gracefully falls back to placeholder on failure. Configured via `WHISPER_API_URL`, `WHISPER_API_KEY`, `WHISPER_MODEL` env vars. No new npm dependencies (uses native fetch)
- **X view tweet tool**: Added `x_view_tweet` MCP tool and `view_tweet.ts` browser script to view a tweet's content (author, text, timestamp, engagement metrics) and optionally load replies. Added `x_view_tweet` to host `scriptMap` in `src/ipc.ts` and to `host.ts` switch. Also added missing `x_bookmarks` case to `host.ts`
- **Upstream merge (v1.2.17 → v1.2.42)**: Merged ~100 upstream commits. Key changes: OneCLI Agent Vault replaces credential proxy, built-in logger replaces pino, task scripts for scheduled tasks, message history overflow fix (`MAX_MESSAGES_PER_PROMPT`), per-group triggers, cursor recovery, shell injection prevention in `stopContainer()`, mount path injection blocking, timezone validation, CLAUDE.md templates for new groups, channel-formatting skill, Emacs channel skill, diagnostics opt-in. Resolved 8 merge conflicts — kept our Telegram channel (upstream moved to skill), tool logging hooks, bot pool config, Parallel AI integration
- **Native credential proxy**: Applied `upstream/skill/native-credential-proxy` to replace OneCLI gateway with built-in `.env`-based credential injection. Simpler setup — no external service needed. Containers get credentials via local HTTP proxy
- **Tool log viewer: pending filter and reverse chrono default**: Added "Pending" result filter chip (with amber styling matching error's red treatment), pending count in stats bar, and changed default sort to newest-first (reverse chronological)
- **Guard tool-log.jsonl from agent modification**: Added pre-tool-use hook that blocks Write, Edit, and Bash tool calls targeting `tool-log.jsonl`. Only the runner's `logTool()` method can append to the file. Wrapped `logTool` in try-catch so serialization errors can't crash the hook and bypass the block check
- **Parallel AI integration**: Added Parallel AI MCP servers (search + deep research task) to agent containers. Host reads `PARALLEL_API_KEY` from `.env` via `readEnvFile()` and passes it to containers. Agent-runner conditionally configures `parallel-search` and `parallel-task` HTTP MCP servers when key is present. Replaced `WebSearch` with Parallel search in allowed tools. Added usage instructions to group CLAUDE.md with guidelines for quick search vs deep research (scheduler-based polling)
- **Tool log viewer**: Added `tools/log-viewer.html` — self-contained browser UI that visualizes agent tool call logs from JSONL files. Pairs pre/post events, shows color-coded tool badges, duration gauges, time gaps, syntax-highlighted args, and supports search/filter/sort. Auto-loads from default group path when served locally. Added `npm run tool-logs` script to serve and open in one command
- **Agent runner tool logging**: Added PreToolUse, PostToolUse, and PostToolUseFailure hooks that log every tool call to `/workspace/group/tool-log.jsonl` as structured JSONL (timestamp, tool name, id, args/response/error)
- **Fix tool log duration**: Replaced `toolResponseDurationSeconds` (only worked for WebSearch) with wall-clock timing — pre hook records `Date.now()` per tool_use_id, post hook computes elapsed seconds. Duration now appears on all tool log entries
- **X (Twitter) integration**: Added browser automation for X via IPC — post, like, reply, retweet, quote. Host spawns Playwright scripts against user's Chrome; container agents access via MCP tools. Main group only. Added playwright + dotenv-cli deps, updated build.sh/Dockerfile for project-root build context, added .dockerignore
- **Container debug scripts**: Added `container:logs` and `container:exec` npm scripts to tail active container logs and shell into the running container
- **Fix container "I have no name!"**: Entrypoint now registers host-mapped UID in `/etc/passwd` so macOS users get a proper username instead of "I have no name!" when exec'ing in
- **Fix group folder references**: Changed `.gitignore`, `src/db.test.ts`, and migration comment in `src/db.ts` from legacy `groups/main/` to `groups/telegram_main/` — the actual active group after machine migration
- **Rename bot**: Renamed assistant from "McClaw" to "miniclaw" — updated default name in `src/config.ts`, `setup/register.ts`, and `groups/global/CLAUDE.md`
- **Commit skill**: Added `/commit` operational skill (`.claude/skills/commit/SKILL.md`) that codifies the project's commit workflow — runs tests, lint, updates FORK_CHANGELOG.md, and creates a conventional commit
- **Container restart script**: Added `container:restart` npm script — builds image, pushes runner, and kills running container in one command. Updated CLAUDE.md docs and "what to run" table
- **Drop project settings in agent runner**: Removed `'project'` from `settingSources` in agent-runner SDK config so container agents only load user-level settings, not project-level
- **CLAUDE.md cleanup**: Removed outdated WhatsApp troubleshooting note (WhatsApp is now a stable skill)

## 2026-03-21

- **Agent runner log format**: Shortened per-message log line from `[msg #N] type=T` to `[#N][T]` for less noise
- **Rename bot**: Renamed assistant from "Andy" to "McClaw" — updated default name in `src/config.ts`, `setup/register.ts`, and `groups/global/CLAUDE.md`. Removed duplicate `groups/main/CLAUDE.md` (main group inherits from global)
- **Development scripts**: Moved shell aliases from `.zshrc` into project-local npm scripts and `scripts/` — service management (`svc.sh`), container testing, runner cache clearing. Added "what to run after changes" reference table to CLAUDE.md
- **container/agent-runner**: Fixed IDE warnings — added explicit types for PreCompact hook callback parameters (HookInput, string | undefined, { signal: AbortSignal })
- **Telegram Agent Swarm**: Added bot pool support for agent teams — each subagent appears as a dedicated bot in Telegram groups
- **docs/SPEC.md**: Fixed trailing whitespace and alignment inconsistencies in ASCII architecture diagram and directory tree
- **FORK_CHANGELOG.md**: Created fork changelog to track all changes diverging from upstream
- **CLAUDE.md**: Added instruction to update FORK_CHANGELOG.md on every commit
