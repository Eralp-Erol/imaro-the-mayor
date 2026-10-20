# Prototyping and Playtesting

Use prototypes to reduce consequential uncertainty. Use playtests to observe the game-player interaction, not to validate the designer's effort.

## Choose Fidelity by Question

| Question | Cheapest useful form |
| --- | --- |
| Is a tradeoff mathematically viable? | spreadsheet or small simulation |
| Does a turn structure create decisions? | paper, cards, tokens, or scripted moderator |
| Can players read state and predict consequences? | interactive mockup with representative feedback |
| Does timing or dexterity feel right? | small real-time digital prototype |
| Do several systems create the intended session rhythm? | integrated playable slice |
| Can production meet visual, technical, and pipeline constraints? | production-quality slice, not a disposable design prototype |

Do not use a polished slice to answer a question that paper can resolve. Do not use paper to claim that timing, controls, audiovisual feedback, or network latency feels correct.

## Hypothesis Card

Complete this before building:

```text
Decision at stake:
Target players and assumed prior knowledge:
Hypothesis:
Competing explanation or alternative:
Prototype must preserve:
Prototype may omit:
Independent variable:
Observed outcomes:
Success range:
Failure signal:
What decision each result changes:
Time and effort cap:
Discard or rewrite plan:
```

A useful hypothesis can fail. "Players will like it" is too vague. "After three turns, at least four of six target players can identify two viable uses for charge and correctly predict which one improves their next turn" is testable.

## Minimal Interactive Loop

For a gameplay prototype, preserve this cycle:

```text
player reads state
player forms an intent
player chooses and acts
rules change state
prototype communicates the result
player gets another consequential choice
```

Include a fast reset and a way to vary the values under test. Keep unrelated systems fixed or replace them with clear proxies.

For an internal-dynamics prototype, player interaction may be absent. Label it a model or simulation and restrict claims to behavior inside the model.

## Prototype Build Sheet

```text
Question:
Loop represented:
States represented:
Rules represented:
Feedback represented:
Controls or moderator actions:
Fixed assumptions:
Known distortions:
Reset procedure:
Values or modes to compare:
Automatic records:
Manual observation fields:
Stop condition:
```

Build in this order:

1. State and reset.
2. One complete interaction loop.
3. Feedback required to interpret that loop.
4. Test controls and logging.
5. Only the additional fidelity needed for the hypothesis.

## Playtest Plan

```text
Research question:
Prototype/build version:
Target participant profile:
Fresh or returning participants:
Number of sessions and session length:
Context given before play:
Task, if directed:
What the moderator may say:
What the moderator must not explain:
Events and decisions to observe:
Metrics to record:
Post-play questions:
Consent, recording, and data-retention notes:
Abort conditions:
Analysis owner and decision date:
```

Use the same opening script for comparable sessions. Tell participants the game is being tested, not their ability. Let them stop at any time. Collect only information needed for the test.

## Observation Sheet

Separate fact from interpretation.

| Time/state | Observable action or quote | Inferred belief | Confidence | Follow-up probe |
| --- | --- | --- | --- | --- |

Useful observations include:

- First element inspected or ignored.
- Time from feedback to next action.
- Choice reversals and comparison behavior.
- Repeated ineffective actions.
- Requests for help or moderator intervention.
- Visible surprise, delight, resignation, or frustration.
- Strategy changes after feedback.
- Whether a participant stops because they achieved the test goal, are blocked, or disengage.

Do not silently repair the experience by coaching. If intervention is necessary, record the exact state, question, and hint.

## Mental-Model Probes

Ask these after the relevant behavior unless thinking aloud is itself the method under test:

- "What do you think just changed?"
- "What caused that result?"
- "What are you trying to make happen next?"
- "What do you expect if you choose this option?"
- "Which information matters for that prediction?"
- "How would you recover from this state?"
- "Explain the rule to another new player."

Use counterfactuals to test transfer rather than recall:

```text
If this value were higher, what would you do differently?
If that option disappeared, what would become more valuable?
If you began the next attempt with this upgrade, what would change first?
```

Compare the participant's model to the actual rule. Classify mismatches:

- Missing cue: relevant information was not noticed.
- Wrong cause: result was attributed to the wrong state or action.
- Wrong direction: player expects increase where the rule decreases, or vice versa.
- Wrong timing: player expects immediate change from a delayed effect.
- Overgeneralization: a local rule is assumed to apply everywhere.
- Exception burden: a previously useful rule fails without a legible reason.

## Measures

Choose only measures that can change the design decision.

### Interaction Measures

- Completion, failure, and abandonment by state.
- Time to first valid action and first successful loop.
- Decision time after relevant information appears.
- Choice share conditional on the options actually available.
- Number of distinct strategies attempted.
- Reversals after new information.
- Recovery rate after a setback.
- Help requests and moderator interventions.

### Understanding Measures

- Prediction accuracy before resolution.
- Rule-explanation accuracy after limited exposure.
- Correct identification of relevant state.
- Confidence compared with accuracy.
- Transfer to a novel but structurally similar situation.

### Experience Measures

Use anchored scales tied to the target, such as:

```text
I could tell why the outcome changed.       1 2 3 4 5 6 7
My choices changed what I did next.         1 2 3 4 5 6 7
I had more than one credible approach.      1 2 3 4 5 6 7
The pace gave me time to use information.   1 2 3 4 5 6 7
```

Balance positive and negative phrasing sparingly; avoid making the survey itself a comprehension test. Behavioral evidence and explanations usually reveal more than a general enjoyment score.

## Analyze and Decide

Immediately after each session, record the strongest observation before discussing it with the team. After the test round:

1. Group repeated observations by state and decision, not by participant personality.
2. Separate usability, comprehension, balance, pacing, and concept-fit problems.
3. Compare behavior, verbal explanation, and recorded state.
4. Look for disconfirming evidence and meaningful outliers.
5. Identify the earliest causal break in each failed trace.
6. Rank findings by impact, frequency, confidence, and cost to test.
7. Select one causal change or next experiment.

Do not claim statistical certainty from a small formative test. Use it for directional learning and follow with broader measurement when the decision requires it.

## Iteration Record

```text
Version/date:
Question tested:
Participants and context:
Change from prior version:
Expected effect:
Observed evidence:
Evidence against the hypothesis:
Unexpected behavior:
Likely cause:
Decision: keep / revise / reject / retest
Next change:
Regression checks to repeat:
```

## Failure Modes

- **Prototype answers several questions:** results cannot identify a cause. Split it into smaller tests.
- **Wrong fidelity:** the medium removes the phenomenon being judged. Increase only the fidelity relevant to that phenomenon.
- **No full loop:** the player cannot act again after feedback. Close the loop before judging engagement.
- **Prototype becomes product:** speed drops because temporary work is being preserved. Reassert the discard boundary or explicitly convert the effort into production work.
- **Designer-only testing:** expertise masks onboarding and interpretation failures. Introduce fresh target players.
- **Fresh-player pool exhausted:** repeated participants remember prior versions. Reserve new participants for learnability milestones.
- **Moderator teaches the rule:** the test measures the explanation, not the game. Record the failure and revise the feedback.
- **Leading questions:** participants mirror the desired answer. Ask for predictions, contrasts, examples, and observed causes.
- **Preference treated as diagnosis:** "make it faster" becomes the solution. Find the state where pace failed and test alternatives.
- **One loud participant dominates:** anecdote replaces pattern. Preserve individual records and compare across sessions.
- **Metrics without context:** choice rates ignore availability, skill, or state. Record the denominator and decision context.
- **Iteration without regression:** a local fix breaks another loop. Re-run the agreed edge traces and prior critical tests.

## Verification Checklist

- The test question is falsifiable and consequential.
- Prototype fidelity matches the question.
- One complete interaction loop exists when testing play.
- Assumptions and omissions are explicit.
- Reset, variants, and state recording work before participants arrive.
- Participant context and moderator script are consistent.
- Observation and interpretation are recorded separately.
- Mental-model probes test prediction, causality, and transfer.
- Findings include counterevidence and uncertainty.
- The resulting decision and next regression checks are documented.
