# Project instructions (Codex and other agents)

This file is kept for non-Claude agents. The studio's operating rules live in `CLAUDE.md`; read it first.

- Creative source of truth: `design/foundation/` (immutable, 2026-10-20) and `design/decisions/`; precedence and historical conflicts in `design/CANON.md`; traceable requirements in `design/REQUIREMENTS.md`.
- The old Codex POC (code, ULTIMATE-CODEX-PROMPT.md, references/) was deleted by the user (D-001, ADR-0003); it is not a reference.
- Prime directive (unchanged): the mayor shapes conditions and builds municipal works; private buildings come only from autonomous actors.
- Architecture: `docs/adr/`. Production state: `production/STATE.md`. Quality gates: `tools/verify.sh`.
- Don't commit secrets; don't push without authorization.
