# Weekly Review Container Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a container skill that guides users through a personal weekly review via adaptive Q&A with AskUserQuestion, running in an isolated context (no session history) to keep reflections clean and focused.

**Architecture:** Single instruction-only SKILL.md in `container/skills/weekly-review/`. The skill has two modes: (1) **Launcher mode** — when invoked in a normal session, it schedules a one-time isolated task via `mcp__nanoclaw__schedule_task`; (2) **Review mode** — when running in the isolated container, it conducts the full guided Q&A. One prerequisite change: add `AskUserQuestion` to the container's allowed tools list.

**Tech Stack:** Markdown (SKILL.md), TypeScript (one-line agent-runner change)

---

### Task 1: Add AskUserQuestion to Container Allowed Tools

**Files:**
- Modify: `container/agent-runner/src/index.ts:470-482`

- [ ] **Step 1: Verify current allowed tools list**

Run:

```bash
grep -n 'AskUserQuestion' container/agent-runner/src/index.ts
```

Expected: no matches (tool is not currently allowed).

- [ ] **Step 2: Add AskUserQuestion to the allowedTools array**

In `container/agent-runner/src/index.ts`, find the `allowedTools` array (around line 470) and add `'AskUserQuestion'` after `'WebFetch'`:

```typescript
      allowedTools: [
        'Bash',
        'Read', 'Write', 'Edit', 'Glob', 'Grep',
        // 'WebSearch',
        'WebFetch',
        'AskUserQuestion',
        'Task', 'TaskOutput', 'TaskStop',
        'TeamCreate', 'TeamDelete', 'SendMessage',
        'TodoWrite', 'ToolSearch', 'Skill',
        'NotebookEdit',
        'mcp__nanoclaw__*',
        'mcp__parallel-search__*',
        'mcp__parallel-task__*'
      ],
```

- [ ] **Step 3: Verify the change compiles**

Run:

```bash
cd container/agent-runner && npx tsc --noEmit
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add container/agent-runner/src/index.ts
git commit -m "feat: add AskUserQuestion to container allowed tools

Enables container skills to use structured Q&A prompts for
interactive workflows like the weekly review skill."
```

---

### Task 2: Create the Weekly Review SKILL.md

**Files:**
- Create: `container/skills/weekly-review/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p container/skills/weekly-review
```

- [ ] **Step 2: Write SKILL.md**

Create `container/skills/weekly-review/SKILL.md` with the following content:

````markdown
---
name: weekly-review
description: Guides a personal weekly review through adaptive Q&A across life areas (health, career, relationships, growth). Reads goals and past reviews from weekly-review/ folder, asks reflective questions via AskUserQuestion, scores each area 1-10, surfaces trends, and saves a structured summary. Use when the user wants to do a weekly review or reflect on their week.
---

# Weekly Review

A guided personal review that reflects on your week across life areas, scores each area, spots trends, and sets priorities for next week.

**Every review runs in an isolated context** — no session history, no conversation carryover. The only context is what the agent reads from the `weekly-review/` folder.

## Mode Detection

This skill operates in two modes. Determine which mode to use:

```bash
echo "${NANOCLAW_SCHEDULED_TASK:-not_scheduled}"
```

Or check if the prompt starts with `[SCHEDULED TASK`:

- **If this is a scheduled/isolated task** → proceed to **Review Flow** below.
- **If this is a normal conversation** → proceed to **Launcher** below.

## Launcher

When invoked from a normal chat session, do NOT run the review inline. Instead, launch it as an isolated task.

### 1. Setup Check

Verify the folder structure exists:

```bash
ls /workspace/group/weekly-review/context/ 2>/dev/null && echo "READY" || echo "NEEDS_SETUP"
```

If `NEEDS_SETUP`, create the structure:

```bash
mkdir -p /workspace/group/weekly-review/context /workspace/group/weekly-review/reviews
```

Then create starter files:

**`/workspace/group/weekly-review/context/areas.md`**:
```markdown
# Life Areas

## Health & Fitness
Exercise, nutrition, sleep, mental health, medical checkups.

## Career & Work
Job performance, projects, skills development, networking.

## Relationships
Family, friends, romantic partner, social life.

## Self-Improvement
Learning, habits, reading, mindfulness, personal growth.
```

**`/workspace/group/weekly-review/context/goals.md`**:
```markdown
# Goals

## Yearly Goals
(Add your yearly goals here)

## Quarterly Goals
(Add your quarterly goals here)

## Current Priorities
(Add your current priorities here)
```

Tell the user: "I've set up the weekly review folder. Please edit the files in `weekly-review/context/` with your actual goals, life areas, and priorities. Then say 'weekly review' when you're ready."

Stop here — don't proceed until context files have real content.

### 2. Schedule Isolated Review

Get the current local time for the schedule:

```bash
date +"%Y-%m-%dT%H:%M:%S"
```

Use `mcp__nanoclaw__schedule_task` with:
- `prompt`: "Run the weekly review skill. Read all files in weekly-review/context/ for goals and life areas. Read the most recent file in weekly-review/reviews/ for last week's review. Then conduct a guided weekly review using AskUserQuestion for each life area: ask reflective questions, get a 1-10 score per area, ask for overall satisfaction, plan next week's priorities with suggestions, surface trends from the last 3-6 reviews, and save the completed review to weekly-review/reviews/YYYY-WNN.md."
- `schedule_type`: `once`
- `schedule_value`: current local timestamp (from the date command above)
- `context_mode`: `isolated`

Tell the user: "Starting your weekly review in a fresh session — you'll get the first question shortly."

## Review Flow

This section runs inside the isolated container. The agent has no session history — only what it reads from disk.

### 1. Load Context

Read all `.md` files in `weekly-review/context/`:

```bash
ls /workspace/group/weekly-review/context/*.md
```

Read each file to understand the user's goals, life areas, and priorities.

### 2. Load Recent History

Find and read the most recent review:

```bash
ls -1 /workspace/group/weekly-review/reviews/*.md 2>/dev/null | sort | tail -1
```

If no previous review exists, note this is the first one.

### 3. Opening

Determine the current week:

```bash
date +"%Y-W%V (%b %d)"
```

Send a brief greeting noting the week number. If a previous review exists, mention 1-2 notable carryovers (missed priorities, streaks, low scores).

### 4. Per-Area Q&A

For each life area in `context/areas.md`, run this loop:

**a) Core question** — Use AskUserQuestion to ask a reflective open-ended question about how this area went. Tailor the question to the area's specifics and any relevant goals or last week's score.

**b) Adaptive follow-up** — Based on the response, decide whether to probe deeper:
- Low energy or negative signals → ask what got in the way
- Missed goals → ask what would help next week
- Breakthroughs or wins → ask what made it work
- Neutral → move on

Ask at most 1-2 follow-ups per area to keep the review moving.

**c) Score** — Use AskUserQuestion to ask for a 1-10 rating. Provide options like:

```
1-3: Struggled significantly
4-5: Below expectations
6-7: Solid / on track
8-9: Strong week
10: Exceptional
```

### 5. Overall Reflection

Use AskUserQuestion to ask:
- Overall satisfaction score (1-10)
- Any cross-cutting thoughts spanning multiple areas

### 6. Next Week Planning

**a)** Use AskUserQuestion to ask: "What are your top priorities for next week?"

**b)** Based on the user's goals and this week's review, suggest 2-3 additional priorities. Use AskUserQuestion with multiSelect to let the user accept or reject each suggestion.

### 7. Trend Snapshot

Read the last 3-6 reviews:

```bash
ls -1 /workspace/group/weekly-review/reviews/*.md 2>/dev/null | sort | tail -6
```

Read each file and extract the scores table. Surface notable patterns:
- Areas trending up or down over 3+ weeks
- Scores that changed significantly week-over-week
- Recurring themes or stalled priorities

Share the trends with the user before saving.

### 8. Save

Determine the filename:

```bash
date +"%Y-W%V"
```

Write the review to `/workspace/group/weekly-review/reviews/YYYY-WNN.md` using this format:

```markdown
# Weekly Review — YYYY-WNN (Mon DD–DD)

## Scores
| Area | Score | Trend |
|------|-------|-------|
| Area Name | N | ↑/→/↓ (was N) |
| ...  | ... | ... |
| **Overall** | **N** | |

## Area Name
[Key reflections and takeaways from the Q&A for this area]

## [Next Area...]
[Reflections]

## Next Week Priorities
- Priority 1 (user-set)
- Priority 2 (user-set)
- Suggested: Priority 3 (agent-suggested, accepted)

## Trends (Last N Weeks)
[Brief narrative of notable patterns across recent reviews]
```

Use ↑ if score increased, ↓ if decreased, → if unchanged vs. last week. If this is the first review, omit the trend column.

Confirm to the user that the review has been saved and give a brief encouraging closing.
````

- [ ] **Step 3: Verify skill file is under 500 lines**

```bash
wc -l container/skills/weekly-review/SKILL.md
```

Expected: well under 500 lines.

- [ ] **Step 4: Commit**

```bash
git add container/skills/weekly-review/SKILL.md
git commit -m "feat: add weekly-review container skill

Guided personal weekly review via adaptive Q&A in isolated context.
Launcher mode schedules a fresh session via schedule_task. Review
mode reads goals, conducts Q&A, scores areas, surfaces trends, and
saves a structured summary."
```

---

### Task 3: Update Changelog, Push Runner, and Deploy

**Files:**
- Modify: `FORK_CHANGELOG.md`

- [ ] **Step 1: Update FORK_CHANGELOG.md**

Add a dated entry to `FORK_CHANGELOG.md` under the most recent section:

```markdown
### 2026-03-29
- **Added weekly-review container skill** — guided personal weekly review via adaptive Q&A in isolated context, with scoring, trends, and next-week planning
- **Added AskUserQuestion to container allowed tools** — enables structured Q&A prompts in container skills
```

- [ ] **Step 2: Commit**

```bash
git add FORK_CHANGELOG.md
git commit -m "docs: update fork changelog for weekly review skill"
```

- [ ] **Step 3: Push the updated agent-runner source**

```bash
npm run container:push-runner
```

This clears cached agent-runner source so the next container spawn picks up the AskUserQuestion change.

- [ ] **Step 4: Deploy**

```bash
npm run deploy
```

This compiles host TypeScript and restarts the service, which will sync the new skill directory on the next container spawn.

- [ ] **Step 5: Verify**

Check that the skill file exists and will be synced:

```bash
ls -la container/skills/weekly-review/SKILL.md
```

In a chat group, send "weekly review" and verify:
1. The agent recognizes the intent and activates the skill
2. If no `weekly-review/` folder exists, it creates the structure with starter files
3. If folder exists, it schedules an isolated one-time task
4. The isolated container runs the review, AskUserQuestion prompts appear
5. The review file is written to `weekly-review/reviews/`
