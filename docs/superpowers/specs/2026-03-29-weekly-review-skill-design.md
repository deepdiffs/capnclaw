# Weekly Review Container Skill — Design Spec

**Date**: 2026-03-29
**Type**: Container skill (instruction-only SKILL.md)
**Location**: `container/skills/weekly-review/SKILL.md`

## Overview

A container skill that guides the user through a personal weekly review via adaptive Q&A. The agent reads the user's goals, life areas, and past reviews from a dedicated folder, then conducts a conversational reflection using AskUserQuestion — scoring each area, surfacing trends, and planning the next week.

## Trigger & Isolation

Manual invocation only. The agent recognizes when the user wants to do a weekly review (e.g., "weekly review", "let's review my week", "time for my review").

**Critical: The review MUST run in an isolated context.** The review should not have access to the group's conversation history or session state. It should only see the files in `weekly-review/context/` and `weekly-review/reviews/`. This prevents session history from polluting the reflective Q&A.

**Mechanism:** When the current-session agent recognizes the intent, it uses `mcp__nanoclaw__schedule_task` to schedule a one-time isolated task:
- `schedule_type: 'once'` — immediate execution (timestamp set to now)
- `context_mode: 'isolated'` — fresh session, no conversation history
- `prompt` — contains instructions to run the weekly review skill

The scheduler picks this up within ~1 minute, spawns a fresh container with no session history, and the skill runs in that clean context. Results are sent back to the user via the channel.

## Folder Structure

The skill expects a `weekly-review/` directory in the group's working directory:

```
weekly-review/
├── context/           # User's life context (read at start)
│   ├── goals.md       # Yearly goals, quarterly goals, priorities
│   ├── areas.md       # Life areas and what matters in each
│   └── ...            # Additional context (calendar, habits, etc.)
├── reviews/           # Completed review output
│   ├── 2026-W12.md
│   ├── 2026-W13.md
│   └── ...
```

- The agent scans `context/` for **all** `.md` files — no hardcoded filenames.
- New context files are automatically picked up (e.g., `calendar.md`, `activity.md`).
- Life areas are defined in `context/areas.md` but the agent may suggest new areas based on patterns.

## Q&A Flow

### Step 1: Load Context
Read all files in `weekly-review/context/` to understand the user's goals, life areas, and priorities.

### Step 2: Load Recent History
Read the most recent review from `weekly-review/reviews/` (latest `YYYY-WNN.md` file).

### Step 3: Opening
Greet the user. Note the current week and any notable carryovers from the last review (missed priorities, ongoing streaks, etc.).

### Step 4: Per-Area Guided Q&A
For each life area found in `context/areas.md`:
- Ask 1-2 core reflective questions via AskUserQuestion.
- Adaptively probe deeper based on the response — explore stress signals, missed goals, breakthroughs, or anything notable.
- Ask for a 1-10 self-rating for the area.

The agent should be smart enough to infer connections across areas and suggest new areas if patterns emerge.

### Step 5: Overall Reflection
Ask for an overall satisfaction score (1-10) and any cross-cutting thoughts that span multiple areas.

### Step 6: Next Week Planning
1. Ask the user: "What are your top priorities for next week?"
2. Based on the user's goals and this week's review, suggest 2-3 additional priorities.
3. Let the user accept, modify, or reject suggestions.

### Step 7: Trend Snapshot
Read the last 3-6 reviews from `weekly-review/reviews/`. Surface notable patterns:
- Areas with consistent improvement or decline
- Scores that have changed significantly
- Recurring themes or unresolved issues

### Step 8: Save
Write the completed review to `weekly-review/reviews/YYYY-WNN.md`.

## Output Format

Each review is saved as a structured markdown file:

```markdown
# Weekly Review — YYYY-WNN (Mon DD–DD)

## Scores
| Area | Score | Trend |
|------|-------|-------|
| Health & Fitness | 7 | ↑ (was 5) |
| Career & Work | 8 | → (was 8) |
| Relationships | 6 | ↓ (was 8) |
| Self-improvement | 9 | ↑ (was 7) |
| **Overall** | **7** | |

## Health & Fitness
[Reflections and key takeaways from the Q&A]

## Career & Work
[Reflections and key takeaways]

## [Other Areas...]
[Reflections and key takeaways]

## Next Week Priorities
- Priority 1 (user-set)
- Priority 2 (user-set)
- Suggested: Priority 3 (agent-suggested, accepted by user)

## Trends (Last N Weeks)
[Brief narrative of notable patterns across recent reviews]
```

- Trend column compares to the previous week's score.
- The Trends section at the bottom covers the last 3-6 weeks.

## Skill Metadata

```yaml
---
name: weekly-review
description: Guides a personal weekly review through adaptive Q&A across life areas (health, career, relationships, growth). Reads goals and past reviews from weekly-review/ folder, asks reflective questions via AskUserQuestion, scores each area 1-10, surfaces trends, and saves a structured summary. Use when the user wants to do a weekly review or reflect on their week.
---
```

## Design Decisions

- **Approach**: Single SKILL.md, purely instructional, no code files or scripts. The agent is smart enough to read context, ask good questions, compute trends from markdown, and write structured output.
- **Isolation**: Every review invocation runs in a fresh isolated container with no session/conversation history. The only context the agent sees is what it reads from `weekly-review/context/` and `weekly-review/reviews/`. This is achieved via `schedule_task` with `context_mode: 'isolated'`.
- **Life areas**: Dynamic — driven by `context/areas.md` contents, not hardcoded in the skill. Agent can suggest new areas.
- **Question depth**: Adaptive — 1-2 core questions per area with deeper probing based on response signals.
- **History window**: 3-6 past reviews for trends — enough for patterns without overwhelming context.
- **Scoring**: 1-10 per area + overall, tracked over time via the review files.
- **Degrees of freedom**: High — the skill gives the agent latitude to adapt questions, follow interesting threads, and make contextual suggestions. This matches the inherently flexible nature of personal reflection.

## Non-Goals

- Not a scheduled/automated task (manual invocation only).
- No external integrations (calendar, health apps) in v1 — but the folder structure supports adding context files for these later.
- No dashboard or visualization — the markdown files are the source of truth.
