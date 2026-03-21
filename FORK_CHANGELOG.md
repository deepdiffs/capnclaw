# Fork Changelog

Changes made in this fork that differ from upstream NanoClaw.

## 2026-03-21

- **Telegram Agent Swarm**: Added bot pool support for agent teams — each subagent appears as a dedicated bot in Telegram groups
  - `src/config.ts`: Added `TELEGRAM_BOT_POOL` config (comma-separated tokens)
  - `src/channels/telegram.ts`: Added `initBotPool()` and `sendPoolMessage()` with round-robin assignment, stable sender→bot mapping, and Markdown formatting
  - `src/ipc.ts`: Route IPC messages with `sender` field through bot pool for `tg:` JIDs, with fallback to main bot
  - `src/index.ts`: Initialize bot pool on startup when tokens are configured
  - `groups/telegram_main/CLAUDE.md`: Created group config with Agent Teams instructions
- **docs/SPEC.md**: Fixed trailing whitespace and alignment inconsistencies in ASCII architecture diagram and directory tree
- **FORK_CHANGELOG.md**: Created fork changelog to track all changes diverging from upstream
- **CLAUDE.md**: Added instruction to update FORK_CHANGELOG.md on every commit
