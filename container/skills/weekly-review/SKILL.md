---
name: weekly-review
description: Conducts a personal weekly review through adaptive Q&A across life areas (health, career, relationships, growth). Reads goals and past reviews from weekly-review/ folder, asks reflective questions via AskUserQuestion, scores each area 1-10, surfaces trends, and saves a structured summary. Runs as a scheduled task every Sunday at 10pm Pacific in isolated context.
---

# Weekly Review

A guided personal review that reflects on your week across life areas, scores each area, spots trends, and sets priorities for next week.

This skill runs as a **scheduled task in isolated context** — no session history, no conversation carryover. The only context is what the agent reads from the `weekly-review/` folder.

## Setup Check

Before starting, verify the folder structure exists:

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

Tell the user: "I've set up the weekly review folder. Please edit the files in `weekly-review/context/` with your actual goals, life areas, and priorities before the next scheduled review."

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
