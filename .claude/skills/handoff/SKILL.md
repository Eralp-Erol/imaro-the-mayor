---
name: handoff
description: Writes Imaro's cross-session checkpoint so the next Claude Code session (or a parallel worktree session) can resume without re-discovery — updates production/STATE.md, appends the daily log, records open questions and unverified claims. Use at the end of a work session, before a long pause or context compaction, when the user says "bitti", "devir", "handoff", "kaydet", "yarın devam", and after finishing or blocking a task.
---

# handoff

`production/STATE.md` is the single resume point (the SessionStart hook injects its checkpoint block). Keep it short and current; history goes to the log.

## Update `production/STATE.md`
Rewrite the `CHECKPOINT` block (≤ 25 lines) with:
- Date, branch, `git rev-parse --short HEAD`, whether the tree is dirty.
- Current milestone and its exit criteria status (x/y).
- Active task(s) and status; **Next** ready task.
- Last verification: mode, result, report path (`artifacts/verify/*-latest.json`), and whether the code changed since (compare `tools/fingerprint.sh` with the report's `fingerprint`).
- Blockers and open questions (Q-ids) waiting for the user.
- Known unverified claims (things built but not yet evidenced).

## Append `production/log/YYYY-MM-DD.md`
3–8 bullets: what changed (task ids, commits), evidence produced, decisions (ADR/D ids), problems found, what is next.

## Rules
- Facts only; mark anything not re-verified this session as such.
- Don't duplicate content that lives in task files/ADRs — link them.
- If this is a worktree session finishing its task and the user said it is done, follow the global git-wt procedure after the checkpoint.
