---
name: game-systems-design
description: "Models engine-agnostic games as interacting parts, state, relationships, feedback, and core/meta loops. Use for cross-system architecture, feedback-loop diagnosis, system boundaries, player mental models, systemic prototypes, and design specifications; defer individual mechanic selection to game-mechanics-design and numerical tuning to game-balance."
license: MIT
metadata:
  author: godot-skills
  version: "1.0.0"
---

# Game Systems Design

Design the behavior of a game across time, not just a list of features. Connect the intended player experience to explicit state, rules, feedback, and evidence.

Remain engine-agnostic. Express behavior with state tables, equations, diagrams, transition rules, and pseudocode unless the user names an implementation environment.

## Core Principles

- Treat the system boundary as a design choice made for a specific question and time horizon.
- Model parts by their state and behavior, then model the relationships that let those parts change one another.
- Distinguish reinforcing feedback, which amplifies change, from balancing feedback, which opposes deviation. Neither is inherently good or bad.
- Define a core loop as the repeated intent-action-state change-feedback cycle holding the player's immediate attention.
- Define a meta loop as a slower cycle that changes the conditions of future core-loop attempts, sessions, or chapters.
- Separate game truth, player-visible evidence, and the player's likely interpretation. A rule the player cannot infer cannot reliably support planning.
- Prefer a few reusable rules with meaningful interactions over many exceptions.
- Prototype the riskiest assumption before polishing or expanding the system.
- Treat playtest comments as evidence of an experience or problem, not automatically as the correct solution.
- Keep intent, model, prototype, implementation, and current evidence traceable to one another.

## Intake

Inspect existing design notes, data, diagrams, builds, tests, and constraints before proposing a replacement. Establish as much of the following as the task needs:

- Player promise: role, desired decisions, emotions, and mastery.
- Audience and context: expected knowledge, session length, player count, and competitive or cooperative setting.
- Design question: the uncertainty or failure being addressed.
- Scope: one encounter, a session, persistent progression, or the full game.
- Current system: parts, rules, resources, interfaces, and known dependencies.
- Constraints: production budget, content budget, accessibility, platform, networking, persistence, and business rules.
- Evidence: observations, playtest notes, telemetry, simulations, or only assumptions.
- Required deliverable and audience.

Do not block on unavailable information. State consequential assumptions, mark unknowns, and identify what evidence would resolve them.

## Workflow

### 1. Frame the Intended Experience

Write a compact target before drawing the system:

```text
The player repeatedly [decision/action] to pursue [goal].
The interesting tension is [tradeoff or uncertainty].
The player should learn [model] and eventually master [skill].
Success looks like [observable behavior or result].
The design must avoid [failure experience].
```

Translate vague qualities into behavior. Replace "deep crafting" with claims such as "players choose among at least two contextually useful recipes and can explain why each fits a different need."

### 2. Set the Boundary and Time Scales

Name what is inside, outside, and crossing the boundary. Specify the smallest meaningful time step and the longest horizon relevant to the question.

Use [System Modeling](references/system-modeling.md) for the boundary worksheet, part inventory, relationship map, feedback analysis, and worked example.

Avoid silently mixing scales. A one-second combat reaction, a ten-minute encounter, and a ten-session upgrade cycle may interact, but each needs its own state and cadence.

### 3. Inventory Parts and Relationships

For every relevant part, record:

- State: mutable values, units, initial values, and bounds.
- Behavior: what it can sense, decide, create, consume, convert, or communicate.
- Ownership: which rule is allowed to change its state.
- Visibility: what the player sees and when.
- Relationships: what crosses to another part, under which condition, and after what delay.

Remove decorative nouns that do not participate in the question. Add missing nonphysical parts such as time, attention, capacity, threat, reputation, or turn order when they materially change behavior.

### 4. Close and Classify Feedback

Trace every important output until it either leaves the boundary or returns to affect an earlier state.

For each closed path:

1. Name the player-facing purpose.
2. Mark each relationship as same-direction or opposite-direction.
3. Classify the loop as reinforcing or balancing.
4. Mark delays, thresholds, caps, and nonlinear regions.
5. Identify who can perturb the loop and what feedback exposes the result.
6. Predict failure at low, normal, high, and adversarial values.

Check reinforcing loops for runaway advantage, compounding scarcity, and irreversible decline. Check balancing loops for sluggishness, oscillation, hidden compensation, and removal of earned advantage.

### 5. Connect Core and Meta Loops

Describe the core loop with verbs, not feature names:

```text
read situation -> choose -> act -> resolve -> perceive result -> choose again
```

Describe every slower loop separately:

```text
complete attempt -> earn or lose persistent resources -> invest -> alter future options -> begin next attempt
```

Then identify each bridge between them. A bridge should explain:

- What leaves the core loop.
- How the meta loop transforms or stores it.
- What returns to a later core loop.
- Whether it expands decisions, merely raises numbers, or invalidates earlier learning.

If the core loop is enjoyable but the meta loop is compulsory bookkeeping, simplify the meta loop. If the meta loop makes the next core attempt automatic, cap or redirect its power.

### 6. Design the Player's Mental Model

For each decision-critical rule, complete this chain:

```text
game state -> perceivable cue -> player interpretation -> prediction -> action -> confirming or correcting feedback
```

Ask whether a new player can notice the cue, connect it to the correct cause, predict a useful consequence, and recover from a wrong model. Preserve uncertainty only when reasoning under uncertainty is part of play.

Do not solve a communication problem by adding explanation alone. First improve rule consistency, state visibility, cause-and-effect timing, and feedback hierarchy.

### 7. Diagnose the System Before Adding Content

Test the model on paper with representative traces:

- First-use trace: no prior knowledge or upgrades.
- Typical trace: expected skill and resources.
- Expert trace: optimized choices and high execution.
- Recovery trace: player begins behind or makes a costly mistake.
- Saturation trace: caps, endgame stocks, and mature strategies.
- Adversarial trace: hoarding, stalling, collusion, degenerate loops, or repeated exploitation.

When a symptom appears, trace backward through relationships before changing a number. The visible failure may be several links away from its cause.

### 8. Prototype One Uncertainty

Choose the cheapest medium that preserves the interaction being tested: paper, cards, spreadsheet, scripted moderator, small simulation, or interactive digital build.

Use [Prototyping and Playtesting](references/prototyping-and-playtesting.md) to write the hypothesis card, test script, observation sheet, mental-model probes, and iteration record.

Every gameplay prototype must let a player form an intent, act, receive a state-dependent result, and choose again. A noninteractive model can test internal dynamics, but it cannot validate the play experience.

### 9. Playtest and Reconstruct Understanding

Run short tests early. Observe before explaining. Capture separately:

- What happened.
- What the player appeared to believe.
- What the player later said.
- What the system recorded.
- What interpretation the team draws.

Ask prediction and explanation questions, not only preference questions. For example: "What do you expect that choice to change?" and "How would you get a different result next time?"

Compare fresh players with returning players. Fresh players reveal learnability; returning players reveal depth, adaptation, and whether earlier knowledge remains useful.

### 10. Revise at the Correct Level

Choose the smallest change that addresses the diagnosed cause:

- Part level: value, bound, state, or local behavior.
- Relationship level: rate, condition, delay, direction, or visibility.
- Loop level: missing brake, weak reward, deadlock, or disconnected bridge.
- Whole-experience level: the system produces a coherent result that does not match the intended game.

Change one causal bundle at a time. Record the hypothesis, expected result, observed result, and decision. Re-run prior edge traces after each structural change.

### 11. Communicate the Current Design

Use [Design Communication](references/design-communication.md) for the one-page brief, system specification, decision log, diagram notation, and handoff checks.

Layer the deliverable:

1. One-page intent and loop summary for alignment.
2. System map and state rules for design review.
3. Data definitions and acceptance checks for implementation.
4. Test evidence and unresolved risks for decision makers.

Keep documents current. Mark proposals, tested behavior, and shipped behavior distinctly.

## Diagnostic Signals

- **Feature inventory, no system:** nouns are listed, but no state-changing relationships close into loops. Add behaviors and trace change over time.
- **Unclear boundary:** the model grows whenever a question is asked. Restate the decision and horizon; convert external detail into explicit inputs or outputs.
- **Runaway leader:** success increases the ability to secure more success faster than counterplay develops. Add costs, exposure, saturation, alternate routes, or a contextual balancing loop.
- **Failure spiral:** losing removes the means to recover. Protect a minimum action budget, create a risky recovery route, or make setbacks change strategy rather than end agency.
- **Oscillation:** a correction repeatedly overshoots its target. Reduce gain, shorten or expose delay, widen tolerance, or damp the response.
- **Dominant path:** one option is best across contexts. Add a real tradeoff or distinct context; do not hide superiority behind complexity.
- **Core/meta disconnect:** rewards do not change later decisions, or persistent power trivializes the core. Redesign the bridge rather than adding another currency.
- **Mental-model break:** similar actions yield inexplicably different outcomes. Remove exceptions, expose conditions, or make feedback more causal.
- **Simulation without play:** internal dynamics look healthy, but the player has no meaningful intervention. Add decision points and observable consequences.
- **Playtest theater:** the prototype is polished but no decision would change from the result. State a falsifiable question before testing.
- **Stale specification:** implementation and documentation disagree. Reconcile them and identify which is authoritative before further iteration.

## Required Deliverables

Unless the user asks for a narrower artifact, produce:

- Experience target and explicit assumptions.
- Boundary, time scales, and dependency list.
- Part/state/behavior inventory.
- Relationship and feedback-loop map.
- Core loop, meta loop, and bridge descriptions.
- Player mental-model and feedback plan.
- Prototype or playtest plan tied to one uncertainty.
- Diagnostics, failure risks, and edge traces.
- Verification criteria and current evidence.
- Decision log or recommended next experiment.

## Verification

Before presenting a design as ready:

- Every important state has an owner, unit or category, initial condition, and bound.
- Every state change has a rule, trigger, and destination.
- Every important loop closes or intentionally exits the boundary.
- Reinforcing loops have known limits; balancing loops have a target and acceptable response time.
- Core and meta loops exchange explicit state without invalidating the intended decisions.
- Decision-critical state has timely, distinguishable feedback.
- A player can state a useful prediction after limited exposure.
- At least one typical, edge, recovery, and exploit trace has been checked.
- The prototype tests the stated uncertainty at appropriate fidelity.
- Evidence is separated from inference, and unknowns remain labeled.
- The communication artifact is precise enough for its audience to make or implement the next decision.
