# Weekly Review Container Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a container skill that guides users through a personal weekly review via adaptive Q&A with AskUserQuestion, reading goals/context and past reviews to produce a scored, structured summary.

**Architecture:** Single instruction-only SKILL.md in `container/skills/weekly-review/`. One prerequisite change: add `AskUserQuestion` to the container's allowed tools list in `container/agent-runner/src/index.ts`. The skill reads from `weekly-review/context/` and writes to `weekly-review/reviews/` in the group directory.

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

In `container/agent-runner/src/index.ts`, find the `allowedTools` array (around line 470) and add `'AskUserQuestion'` after the existing tool entries:

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

```markdown
---
name: weekly-review
description: Guides a personal weekly review through adaptive Q&A across life areas (health, career, relationships, growth). Reads goals and past reviews from weekly-review/ folder, asks reflective questions via AskUserQuestion, scores each area 1-10, surfaces trends, and saves a structured summary. Use when the user wants to do a weekly review or reflect on their week.
---

# Weekly Review

A guided personal review that reflects on your week across life areas, scores each area, spots trends, and sets priorities for next week.

## Setup Check

Before starting, verify the folder structure exists:

```bash
ls /workspace/group/weekly-review/context/ 2>/dev/null && echo "READY" || echo "NEEDS_SETUP"
```

If `NEEDS_SETUP`, create the structure and tell the user to populate it:

```bash
mkdir -p /workspace/group/weekly-review/context /workspace/group/weekly-review/reviews
```

Then create starter files:

**`/workspace/group/weekly-review/context/areas.md`** — life areas to review:
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

**`/workspace/group/weekly-review/context/goals.md`** — placeholder for goals:
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

Stop here — don't proceed with the review until context files have real content.

## Review Flow

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
```

- [ ] **Step 3: Verify skill file is under 500 lines**

```bash
wc -l container/skills/weekly-review/SKILL.md
```

Expected: well under 500 lines.

- [ ] **Step 4: Commit**

```bash
git add container/skills/weekly-review/SKILL.md
git commit -m "feat: add weekly-review container skill

Guided personal weekly review via adaptive Q&A. Reads goals and
past reviews, scores each life area 1-10, surfaces trends, and
plans next week's priorities."
```

---

### Task 3: Push Runner and Test

**Files:**
- No file changes — runtime verification only.

- [ ] **Step 1: Push the updated agent-runner source**

```bash
npm run container:push-runner
```

This clears cached agent-runner source so the next container spawn picks up the AskUserQuestion change.

- [ ] **Step 2: Verify the skill is synced into a group**

Check that the skill directory will be copied on next container start:

```bash
ls container/skills/weekly-review/SKILL.md
```

Expected: file exists. The container-runner's skill sync loop (`src/container-runner.ts:151-161`) copies all directories from `container/skills/` into each group's `.claude/skills/` on every container spawn.

- [ ] **Step 3: Deploy if service is running**

```bash
npm run container:push-runner && npm run deploy
```

This ensures the host picks up the new skill directory for syncing.

- [ ] **Step 4: Test manually**

In a chat group, send "weekly review" and verify:
1. The agent recognizes the intent and activates the skill
2. It checks for the `weekly-review/` folder and runs setup if missing
3. AskUserQuestion prompts appear with structured options
4. The review file is written to `weekly-review/reviews/`

- [ ] **Step 5: Commit FORK_CHANGELOG.md update**

Add a dated entry to `FORK_CHANGELOG.md`:

```markdown
### 2026-03-29
- **Added weekly-review container skill** — guided personal weekly review via adaptive Q&A across life areas with scoring, trends, and next-week planning
- **Added AskUserQuestion to container allowed tools** — enables structured Q&A prompts in container skills
```

```bash
git add FORK_CHANGELOG.md
git commit -m "docs: update fork changelog for weekly review skill"
```
