# Fork Changelog

Changes made in this fork that differ from upstream NanoClaw.

## 2026-03-28

- **Rename bot**: Renamed assistant from "McClaw" to "miniclaw" — updated default name in `src/config.ts`, `setup/register.ts`, and `groups/global/CLAUDE.md`

## 2026-03-21

- **Agent runner log format**: Shortened per-message log line from `[msg #N] type=T` to `[#N][T]` for less noise
- **Rename bot**: Renamed assistant from "Andy" to "McClaw" — updated default name in `src/config.ts`, `setup/register.ts`, and `groups/global/CLAUDE.md`. Removed duplicate `groups/main/CLAUDE.md` (main group inherits from global)
- **Development scripts**: Moved shell aliases from `.zshrc` into project-local npm scripts and `scripts/` — service management (`svc.sh`), container testing, runner cache clearing. Added "what to run after changes" reference table to CLAUDE.md
- **container/agent-runner**: Fixed IDE warnings — added explicit types for PreCompact hook callback parameters (HookInput, string | undefined, { signal: AbortSignal })
- **Telegram Agent Swarm**: Added bot pool support for agent teams — each subagent appears as a dedicated bot in Telegram groups
- **docs/SPEC.md**: Fixed trailing whitespace and alignment inconsistencies in ASCII architecture diagram and directory tree
- **FORK_CHANGELOG.md**: Created fork changelog to track all changes diverging from upstream
- **CLAUDE.md**: Added instruction to update FORK_CHANGELOG.md on every commit
