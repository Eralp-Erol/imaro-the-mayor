---
name: canon-check
description: Checks an Imaro request, task, design spec, plan or implementation against the game's creative canon (design/foundation, design/decisions, design/REQUIREMENTS.md), classifies each relevant point as KANONİK / ONAYLANMIŞ YÖN / ÇALIŞMA MODELİ / AÇIK / REDDEDİLDİ, detects conflicts, resolves them by the documented precedence rules, and turns genuinely open creative questions into grouped entries in production/QUESTIONS.md. Use whenever work touches gameplay, world/geography, politics, economy, names, art direction or UX; whenever someone proposes changing an established decision; before writing a design spec; and when a user request seems to contradict earlier decisions — even if nobody says "canon".
---

# Canon check

Purpose: stop the studio from building a technically working but creatively wrong game, without blocking routine technical work.

## Inputs
The thing to check (task file, spec, diff summary, user request, screenshot description) and, if known, its REQ ids.

## Procedure
1. **Locate.** Map the topic to REQ ids with the lookup table below, then open only the cited foundation sections (`grep -n '^#' design/foundation/docs/*.md` to find headings). Also scan `design/decisions/` (newest first) — later explicit user decisions win.
2. **Classify** every claim/choice in the input that touches canon:
   - KANONİK → binding; any contradiction is a conflict.
   - ONAYLANMIŞ YÖN → direction is binding, specific objects/coordinates are not.
   - ÇALIŞMA MODELİ → usable, must stay tunable; must not be presented as fixed fact/number/name.
   - AÇIK → must not be decided by the studio; implement data-driven or ask.
   - REDDEDİLDİ → must not reappear.
   - TEKNİK → not a creative matter; the studio decides (ADR).
3. **Resolve conflicts** using `design/CANON.md` precedence: later user decision > written rule > approved image direction; approved image ≠ coordinates; working model ≠ fixed fact. If precedence settles it, state the resolution and cite both sources. If not, it is a question for the user.
4. **Escalate** only genuine creative questions. Append to `production/QUESTIONS.md` using the format below; group related questions; include a recommendation and what the studio will do meanwhile (a reversible default or a parked task). Never block unrelated work.
5. **Record user answers** (only when the user actually answered in chat): `design/decisions/D-NNN-<slug>.md` with date, the user's words quoted, what it supersedes, affected REQ ids; then update `design/REQUIREMENTS.md` and close the question.

## Output format
```
CANON CHECK — <subject>
Verdict: CLEAR | CLEAR WITH CONDITIONS | CONFLICT | NEEDS USER DECISION
Touches: <REQ ids>
- [KANONİK|OY|ÇM|AÇIK|RED|TEKNİK] <point> — <source file §section> — <ok / conflict / condition>
Resolutions: <precedence-based resolutions, with both citations>
Questions added: <Q-ids or none>
Safe to proceed with: <what can be built now without deciding the open items>
```

## QUESTIONS.md entry format
```
### Q-NNN · <short title>  (status: open | blocked | answered → D-NNN)
- Context: <why it matters now; which task/REQ is affected>
- Options: A) … B) … C) …
- Recommendation: <option + one-line reason>
- Blocks: <task ids, only if status is blocked; open = blocks nothing>
- Meanwhile: <reversible default / parked tasks>
```

## Topic → REQ lookup (high-risk rules)
| Topic | REQ | Foundation |
|---|---|---|
| Names; Orven role; inventing names | CAN-01, WLD-10 | F01 "Dünya", F05-A |
| Placing private buildings / god-mode | CAN-03, SIM-07 | F03 "Kritik", F05-A |
| Roads, parks, public works drawn by player | CAN-04 | F03 mod 1 |
| Zoning / density | CAN-05 | F03 mod 2 |
| Council, budget, elections, parties, legal powers | CAN-06, CAN-10 (+ OPEN: F05-D) | F03 "Politik gelişme", F05-D |
| Protagonist / campaign arc / finale | CAN-07, CAN-09, CAN-11 | F01 "Bir kampanyanın hikâyesi" |
| Starting district selection / Orven mandatory | CAN-08, WLD-12 | F01, F05-A, F05-E |
| Zoom levels, LOD, separate maps | WLD-01, TEK-03 | F02 "Alt ölçek sözleşmesi" |
| Port, industry, islands at T0 | WLD-03 | F02 "Liman/ada kuralı" |
| D1–D6, T0 density, D1/D6 relation | WLD-02, WLD-04, WLD-05, WLD-06 | F02 atlas |
| Clock tower, stadium, ruins, heritage | WLD-07 | F02 "İzmir'den esinlenen", F04 |
| Happiness/popularity metric | SIM-09 | F03 |
| Art style, references, rejected looks | VIS-01..07 | F04, F05-E |
| Currency (name/symbol) | OPEN — user-confirmed (Q-003); config only, placeholder `¤` | — |
| Starting district | CAN-08 + D-002 (player chooses; studio test area ≠ design decision) | F01, F05-A, D-002 |
| Platforms, input/UI/graphics profiles, iPad limits | PLT-01..06 (D-003), ADR-0004 | D-003 |

## Validation
A correct run (a) cites a concrete file/section for every classification, (b) never turns an AÇIK item into a fact, (c) catches these known traps: port or main industry on an island at T0; Orven as forced start; a "Residential" build button for the player; one happiness %; clock tower towering over 5-floor blocks; different coastline per zoom; inventing party/election names.
