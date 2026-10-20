---
name: dev-task
description: Runs one Imaro production task end-to-end as the Studio Director — read the task file, canon pre-flight, route to the right specialist(s), implement, run quality gates, get independent review, record evidence and update production state. Use when the user says to work on / continue / do a task (e.g. "/dev-task T-004", "devam et", "sıradaki görevi yap"), or when picking the next task from production/STATE.md.
argument-hint: "[T-NNN]  (omit to take the next ready task from production/STATE.md)"
---

# dev-task — one task, fully closed

Input: `$ARGUMENTS` = task id, or empty → take `Next` from `production/STATE.md` (if none: run `plan-milestone`).

## 0. Load (cheap)
Read `production/STATE.md`, the task file `production/tasks/T-NNN.md`, and the ADRs it links. Do not re-read the whole foundation; use the REQ ids.

## 1. Readiness gate
The task must have: goal, REQ ids, acceptance criteria that a player/tester can observe, evidence plan, owner discipline, dependencies done. Missing → fix the task file first (small) or run `plan-milestone`.
If the task touches gameplay/world/politics/economy/art/UX → run `canon-check` (or delegate to `design-director` when the task is large/ambiguous). `NEEDS USER DECISION` on the critical path → add the question, mark the task `blocked`, move to the next ready task. Do not guess.

## 2. Route
Use the routing table in `CLAUDE.md`. Rules:
- Small, single-domain change (≲ 1 file / obvious) → do it yourself.
- Otherwise brief the owning specialist with: task path, REQ ids, acceptance criteria, files/dirs it may write, verification it must run, and what to return. Always pass `model` explicitly (`sonnet` for specialists, `opus` only for directors).
- Independent sub-parts in different files → parallel agents; shared files → sequential.
- Cross-discipline dependency (e.g. sim field needed by UI) → sequence them; the producer of the interface goes first and documents it in the task file.

## 3. Verify (never skip)
- `tools/verify.sh quick` after each implementation step; `tools/verify.sh full` before calling the task done.
- Presentation-sensitive → `visual-gate` with real captures; behaviour → scenario tests; performance-sensitive → measurements vs ADR-0001.
- Failing gate → `systematic-debugging`; fix root cause; re-run. Three failed fix attempts on the same issue → stop and escalate to `technical-director` with evidence.

## 4. Independent review
- Always: `qa-engineer` checks every acceptance criterion against evidence (it must not be the implementer).
- Plus, by type: architecture/new subsystem → `technical-director`; gameplay/world/politics fidelity → `design-director`; visible output → `art-director`. Milestone-closing tasks get all relevant directors.
- Reviewers' `FAIL`/`DEVIATES` → back to step 2 with their findings. Disagreement between reviewers → `technical-director` (technical) or user question (creative).

## 5. Record & close
- Task file: status `done` only if every criterion is PASS with evidence; otherwise `in-review`/`blocked` with the reason. Fill the Evidence section (commands + results, screenshot paths, review verdicts) and REQ evidence level in `design/REQUIREMENTS.md` when it changed.
- `production/STATE.md` checkpoint (current milestone, last verified state, next task). Append a short entry to `production/log/YYYY-MM-DD.md`.
- Commit on the current branch with `T-NNN` in the title (no push).

## Failure modes to avoid
Declaring done from a passing build; reviewing your own work; screenshots you did not open; inventing open creative facts; agent chatter instead of code; parallel writers on the same file.
