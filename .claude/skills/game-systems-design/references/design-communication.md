# Design Communication

Communicate enough intent for decisions and enough precision for implementation without creating one monolithic document that immediately becomes stale.

## Layer the Artifacts

| Artifact | Audience | Purpose | Update trigger |
| --- | --- | --- | --- |
| One-page system brief | whole team and stakeholders | align on purpose, loops, and risks | intent or scope changes |
| System specification | design, engineering, content, QA | define state, rules, interfaces, and feedback | behavior changes |
| Data dictionary | design, engineering, analytics | define fields, units, bounds, and ownership | schema changes |
| Test record | design, research, QA | preserve evidence and decisions | every test round |
| Decision log | everyone affected | explain why the current design exists | every accepted or rejected change |

Link these artifacts. Do not duplicate detailed values in prose if a single authoritative table can be linked instead.

## Neutral Diagram Notation

Use a small legend and apply it consistently:

```text
[Part | state] ----resource/information----> [Part | state]
                    + same-direction effect
                    - opposite-direction effect
                    // delayed effect
                    ? conditional effect

R: closed reinforcing path
B: closed balancing path
```

Every arrow label should say what crosses the relationship. "A affects B" is incomplete; "cargo increases fuel cost per leg after departure" is actionable.

Create separate views when one diagram must show too many levels:

- Context view: system boundary, peers, and external interfaces.
- Loop view: core, meta, reinforcing, and balancing paths.
- Detail view: part state, transitions, equations, and events.
- Player view: information, actions, feedback, and hidden state.

## One-Page System Brief Template

```markdown
# <System Name>

## Purpose
<Player-facing experience and why this system exists.>

## Scope
<Boundary, time horizon, included and excluded concerns.>

## Player Decisions
- <Decision, information used, and tradeoff.>

## Core Loop
<Verb sequence and expected duration.>

## Meta Connection
<What persists, how it changes future play, and reset behavior.>

## Key State and Resources
- <Name, meaning, unit, owner, visibility.>

## Feedback Structure
- Reinforcing: <path, benefit, limit.>
- Balancing: <path, target, delay.>

## Success Evidence
- <Observable player behavior or measurable result.>

## Risks and Unknowns
- <Failure mode, assumption, or next experiment.>
```

## System Specification Template

```markdown
# <System Name> Specification

Status: proposed | prototyped | validated | implemented | shipped
Owner:
Last verified against build/data version:

## Intent and Non-Goals
<What experience this supports and what it deliberately does not model.>

## Boundary and Dependencies
- Inputs:
- Outputs:
- Peer systems:
- Persistent interfaces:

## State Model
| State | Type/unit | Initial | Valid range | Owner | Player visibility |
| --- | --- | --- | --- | --- | --- |

## Behaviors and Transitions
| Trigger | Guard | Inputs | State change | Outputs | Feedback | Delay |
| --- | --- | --- | --- | --- | --- | --- |

## Loop Map
<Diagram plus core/meta and reinforcing/balancing descriptions.>

## Rules and Equations
<Precise formulas, rounding order, priorities, and tie handling.>

## Player Communication
<Cues before commitment, resolution feedback, and recovery guidance.>

## Edge Cases
- Minimum state:
- Maximum state:
- Simultaneous events:
- Disconnect/reload/reset:
- Invalid or missing data:
- Exploit attempts:

## Acceptance Checks
- Given <state>, when <action>, then <observable result>.

## Evidence
<Prototype, playtest, simulation, telemetry, and known limitations.>

## Open Questions
- <Question, owner, evidence needed, decision date.>
```

## Rule Writing

Write rules in present tense with explicit conditions and outcomes.

Weak:

```text
Heavy cargo may make travel a bit harder.
```

Precise:

```text
When the skiff departs, each cargo unit above 6 increases that leg's fuel cost by 4%, calculated before rounding. The route preview displays the resulting cost range before confirmation.
```

For every rule, specify:

- Trigger and evaluation order.
- Required state and guard conditions.
- Consumed, created, or transferred values.
- Formula, unit, bounds, and rounding.
- Immediate and delayed results.
- Player-facing feedback.
- Behavior when data is missing or several rules fire together.

## Traceability Matrix

Use one row per important promise.

| Experience target | Player decision | Supporting rule/loop | Player cue | Evidence | Status |
| --- | --- | --- | --- | --- | --- |

This catches attractive features that do not support the intended experience and intended experiences with no implemented support.

## Decision Log Template

```markdown
## <Date> - <Decision>

- Context:
- Evidence:
- Options considered:
- Decision:
- Why this option:
- Expected effect:
- Risks and guardrails:
- Rejected alternatives and why:
- Owner:
- Revisit condition or date:
```

Record rejected paths briefly. Otherwise, the same unresolved argument will recur after team memory fades.

## Change Proposal Template

```markdown
# Change: <Short Name>

Observed problem:
Affected players/context:
Earliest causal break:
Current behavior:
Proposed behavior:
Level changed: part | relationship | loop | experience
Expected metric or observation movement:
Unchanged guardrails:
Prototype/test plan:
Regression risks:
Rollback condition:
Documents/data/tests to update:
```

## Review Prompts by Discipline

- **Design:** Are the decisions viable, legible, and connected across time scales?
- **Engineering:** Are state ownership, event order, bounds, persistence, and failure behavior explicit?
- **Art/audio/UI:** Which state changes need cues, at what priority and cadence?
- **Content/level design:** Which ranges and assumptions must authored content respect?
- **QA:** Which invariants, edge cases, exploits, and regressions matter?
- **Analytics/research:** Which question requires evidence, and what context must be recorded?
- **Production:** Which dependencies, unknowns, and approval points threaten scope?

## Communication Failure Modes

- **Diagram without semantics:** arrows have no resource, sign, or condition. Label the relationship.
- **Prose without state:** qualitative intent cannot be implemented. Add state and acceptance checks.
- **Numbers without rationale:** later tuning destroys an important tradeoff. Link values to the target and evidence.
- **One document for every audience:** no one can find their level of detail. Split and link layered artifacts.
- **Status ambiguity:** a proposal is mistaken for shipped behavior. Mark status and verified version prominently.
- **Duplicate authority:** prose, sheet, and implementation contain different values. Name one source of truth for each datum.
- **Unrecorded rejection:** discarded ideas repeatedly return. Preserve concise decision history.
- **Documentation after implementation:** hidden assumptions become accidental rules. Update the specification with the behavior change.

## Handoff Verification

- A reader can explain why the system exists after reading the brief.
- A designer can trace core and meta loops without oral clarification.
- An implementer can identify state owners, order, units, bounds, and error behavior.
- UI, art, and audio can identify every decision-critical cue.
- QA can derive typical, edge, recovery, and exploit tests.
- A researcher can state the unresolved question and required evidence.
- Every linked artifact exists, has an owner, and identifies its current status.
- No critical rule lives only in a meeting, chat thread, or person's memory.
