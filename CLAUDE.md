# NanoClaw

Personal Claude assistant. See [README.md](README.md) for philosophy and setup. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for architecture decisions.

## Quick Context

Single Node.js process with skill-based channel system. Channels (WhatsApp, Telegram, Slack, Discord, Gmail) are skills that self-register at startup. Messages route to Claude Agent SDK running in containers (Linux VMs). Each group has isolated filesystem and memory.

## Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Orchestrator: state, message loop, agent invocation |
| `src/channels/registry.ts` | Channel registry (self-registration at startup) |
| `src/ipc.ts` | IPC watcher and task processing |
| `src/router.ts` | Message formatting and outbound routing |
| `src/config.ts` | Trigger pattern, paths, intervals |
| `src/container-runner.ts` | Spawns agent containers with mounts |
| `src/task-scheduler.ts` | Runs scheduled tasks |
| `src/db.ts` | SQLite operations |
| `groups/{name}/CLAUDE.md` | Per-group memory (isolated) |
| `container/skills/` | Skills loaded inside agent containers (browser, status, formatting) |

## Skills

Four types of skills exist in NanoClaw. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full taxonomy and guidelines.

- **Feature skills** — merge a `skill/*` branch to add capabilities (e.g. `/add-telegram`, `/add-slack`)
- **Utility skills** — ship code files alongside SKILL.md (e.g. `/claw`)
- **Operational skills** — instruction-only workflows, always on `main` (e.g. `/setup`, `/debug`)
- **Container skills** — loaded inside agent containers at runtime (`container/skills/`)

| Skill | When to Use |
|-------|-------------|
| `/setup` | First-time installation, authentication, service configuration |
| `/customize` | Adding channels, integrations, changing behavior |
| `/debug` | Container issues, logs, troubleshooting |
| `/update-nanoclaw` | Bring upstream NanoClaw updates into a customized install |
| `/qodo-pr-resolver` | Fetch and fix Qodo PR review issues interactively or in batch |
| `/get-qodo-rules` | Load org- and repo-level coding rules from Qodo before code tasks |

## Fork Changelog

Every commit MUST include an update to [FORK_CHANGELOG.md](FORK_CHANGELOG.md). Add a dated entry describing what changed and why. This tracks all divergences from upstream NanoClaw.

## Contributing

Before creating a PR, adding a skill, or preparing any contribution, you MUST read [CONTRIBUTING.md](CONTRIBUTING.md). It covers accepted change types, the four skill types and their guidelines, SKILL.md format rules, PR requirements, and the pre-submission checklist (searching for existing PRs/issues, testing, description format).

## Development

Run commands directly—don't tell the user to run them.

```bash
npm run dev              # Hot-reload dev mode
npm run build            # Compile TypeScript
npm run lint             # Typecheck (tsc --noEmit)
npm test                 # Run all tests
npm run test:watch       # Tests in watch mode
npm run deploy           # Build + restart service
```

Service management:
```bash
npm run svc start        # Start the background service
npm run svc stop         # Stop the background service
npm run svc restart      # Restart the background service
npm run svc status       # Show service status
npm run svc:logs         # Tail the main log
npm run svc:errors       # Tail the error log
```

Container management:
```bash
npm run container:build        # Rebuild agent container image
npm run container:build:clean  # Prune cache + rebuild (for stale COPY layers)
npm run container:test         # Test container with a prompt
npm run container:push-runner  # Clear cached agent-runner source for all groups
npm run container:logs         # Tail logs for the active container
npm run container:exec         # Shell into the active container
```

What to run after making changes:

| What changed | Command | Why |
|---|---|---|
| Host code (`src/`) | `npm run deploy` | Compiles TS + restarts service |
| Agent runner (`container/agent-runner/src/`) | `npm run container:push-runner` | Clears cached source; fresh copy mounted on next container spawn |
| Both | `npm run container:push-runner && npm run deploy` | |
| Container Dockerfile or dependencies | `npm run container:build` | Need a new image |
| Container Dockerfile + stale cache | `npm run container:build:clean` | Prunes buildkit then rebuilds |

If running `npm run dev` while the service is active, stop the service first:
```bash
npm run svc stop && npm run dev
# When done (ctrl-c), restart the service:
npm run svc start
```

## Troubleshooting

**WhatsApp not connecting after upgrade:** WhatsApp is now a separate skill, not bundled in core. Run `/add-whatsapp` (or `npx tsx scripts/apply-skill.ts .claude/skills/add-whatsapp && npm run build`) to install it. Existing auth credentials and groups are preserved.

## Container Build Cache

The container buildkit caches the build context aggressively. `--no-cache` alone does NOT invalidate COPY steps — the builder's volume retains stale files. Use `npm run container:build:clean` to prune the builder and rebuild from scratch.
