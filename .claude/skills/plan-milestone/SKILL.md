---
name: plan-milestone
description: Converts Imaro's requirements and roadmap into an executable milestone — a small set of vertical-slice tasks with observable acceptance criteria, REQ traceability, discipline owners, dependencies and evidence plans — and updates production/ROADMAP.md, production/STATE.md and production/tasks/. Use when starting a milestone, when the backlog has no ready task, when scope changes after a user decision, or when the user asks to plan/re-plan ("planla", "sonraki milestone", "roadmap").
argument-hint: "[milestone id, e.g. M1]"
---

# plan-milestone

## Principles
- Vertical slices over horizontal layers: each milestone ends with something playable/observable in the real 3D world that proves a slice of the core fantasy (F03 loop), not "all of the sim" or "all of the art".
- Small credible slice > wide fake simulation. Prefer 5–10 tasks per milestone, each ≤ ~1 day of agent work.
- Every task traces to REQ ids; every milestone states which REQs it advances and to what evidence level (T/R/P/U).
- Do not schedule work that depends on an OPEN creative decision without either a reversible default or a question in `production/QUESTIONS.md`.

## Procedure
1. Read `production/ROADMAP.md` (milestone goal + exit criteria), `production/STATE.md`, `design/REQUIREMENTS.md`, relevant ADRs. Run `canon-check` on the milestone goal.
2. Draft tasks with `production/tasks/_TEMPLATE.md`. For each: goal, REQ ids, acceptance criteria (observable; include at least one negative case for behaviour), evidence plan (which test/capture/measurement), owner (agent name), reviewers, dependencies, files/areas.
3. Order by dependency; mark which can run in parallel (disjoint files).
4. Sanity pass (as Studio Director, or `technical-director` + `design-director` for a new milestone): does completing all tasks actually satisfy the milestone exit criteria? Any task that only produces documents must justify itself.
5. Write task files, update ROADMAP (task list under the milestone) and STATE (`Next`). Log the plan in `production/log/`.

## Output
Milestone summary (goal, exit criteria, REQs advanced), task table (id, title, owner, depends on, parallel group), open questions raised.
