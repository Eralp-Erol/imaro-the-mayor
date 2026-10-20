# System Modeling

Use this reference to turn an experience goal into a bounded model of state, relationships, feedback, and player-facing loops.

## Boundary Worksheet

```text
Design question:
Player-facing purpose:
Decision this model must support:
Smallest time step:
Longest relevant horizon:
Included actors and processes:
Explicitly excluded detail:
Inputs crossing inward:
Outputs crossing outward:
Persistent state crossing sessions:
Assumptions about the surrounding game:
```

A boundary is useful when it contains everything that can materially change the answer during the chosen horizon, while representing the rest as named inputs, outputs, or assumptions.

Revisit the boundary if the model cannot explain an observed result. Do not expand it merely because more detail exists.

## Part Inventory

Record one row for each functional part.

| Field | Question |
| --- | --- |
| ID and name | Can every diagram and rule refer to it unambiguously? |
| Role | Is it an actor, stock, source, sink, converter, gate, timer, or interface? |
| State | Which values can change? |
| Unit and bounds | What makes values comparable and valid? |
| Initial condition | What exists when the model starts? |
| Behaviors | What can this part create, consume, transform, sense, or signal? |
| Ownership | Which rule may mutate each state value? |
| Visibility | What can the player observe directly or infer? |
| Persistence | Does it reset per action, encounter, session, or never? |

Use as few states as can preserve the intended decisions. Split a part into a subsystem only when its internal choices or dynamics matter to the player, the model, or production ownership.

## Relationship Worksheet

Relationships, not proximity, make a collection into a system.

| From | To | What crosses | Rule or rate | Direction | Delay | Condition | Player cue |
| --- | --- | --- | --- | --- | --- | --- | --- |
| part/state | part/state | resource, information, permission, risk | equation or transition | same or opposite | time/turns | gate | observable feedback |

Use "same" when increasing the source tends to increase the destination relative to its prior value. Use "opposite" when increasing the source tends to decrease it. Classify within a stated operating range; nonlinear relationships can change direction.

For a stock updated in discrete steps:

```text
stock_next = clamp(stock_now + sum(inflows) - sum(outflows), minimum, maximum)
```

For event-driven state:

```text
when trigger and guard are true:
    consume inputs
    apply transition
    emit outputs and feedback
```

Write units beside every term. Adding "3 tokens" to "2 tokens per minute" is a modeling error until a duration converts the rate into an amount.

## Feedback Analysis

A closed path is reinforcing when a perturbation eventually returns in the same direction. It is balancing when it returns in the opposite direction.

For a loop whose links are marked `+1` for same-direction and `-1` for opposite-direction:

```text
loop_polarity = product(link_signs)
```

- `+1`: reinforcing.
- `-1`: balancing.

Polarity predicts direction, not strength. Also record sensitivity, thresholds, caps, and delays.

### Loop Card

```text
Loop name:
Player-facing purpose:
Path through states:
Polarity:
Main resource or information:
Who can perturb it:
Approximate strength:
Delay before response:
Thresholds and caps:
Expected operating range:
Player-visible evidence:
Failure below range:
Failure above range:
Counter-loop or escape route:
```

### Reinforcing Feedback Checks

- What compounds: capacity, information, access, score, wealth, risk, or debt?
- Does early variance become permanent advantage or disadvantage?
- What limits growth: cap, congestion, upkeep, exposure, saturation, competition, or reset?
- Does growth expand decisions, or only make the same action numerically larger?
- Can a player intentionally trade present power for future power?
- Can the loop start from the minimum state, or is it deadlocked?

### Balancing Feedback Checks

- What target or acceptable band is being maintained?
- Does correction respond to absolute state, rate of change, or distance from target?
- Is the correction visible and attributable?
- Does delay cause overshoot or repeated oscillation?
- Does the mechanism preserve earned differences that the game is meant to reward?
- Can players manipulate the measurement to gain a hidden advantage?

## Hierarchy and Time Scales

Model each scale separately before connecting it.

```text
Moment: input, immediate resolution, local feedback
Encounter: resource attrition, adaptation, short-term objective
Session: route, build, match, mission, or run outcome
Meta: persistent unlocks, reputation, collection, or strategic preparation
Community/world: shared markets, factions, seasons, or long-lived population state
```

At each level, name the aggregate state created by lower-level interactions. Do not duplicate the same state independently at two levels without a reconciliation rule.

## Core Loop Worksheet

The core loop is not merely the fastest loop. It is the repeated interaction currently carrying the player's central decision-making.

| Step | Prompt |
| --- | --- |
| Read | What situation can the player perceive? |
| Intend | Which goal or prediction do they form? |
| Choose | What viable alternatives exist? |
| Act | Which input or commitment expresses the choice? |
| Resolve | Which rules change state? |
| Feedback | What reveals cause, magnitude, and new opportunity? |
| Continue | Why is another decision now interesting? |

Write the loop once as verbs only, then once with concrete game nouns. If the verb-only version is "wait -> collect -> wait," adding more nouns will not create a richer decision.

## Meta Loop Worksheet

```text
Core-loop output:
Persistent stock or record:
Conversion or investment decision:
Future condition changed:
New opportunity, constraint, or strategy:
Reset behavior:
Time to complete one meta cycle:
How prior learning remains useful:
```

### Bridge Audit

For every core/meta bridge, ask:

- Is the transferred resource legible before the player commits?
- Does the meta reward create a new decision, increase tolerance, or only inflate output?
- Does a reset preserve knowledge, expression, or strategic identity?
- Can meta power erase the need to engage with the core mechanics?
- Can poor core performance remove all access to recovery in the meta layer?

## Player Mental-Model Worksheet

| Game truth | Cue | Intended interpretation | Useful prediction | Test action | Correction if wrong |
| --- | --- | --- | --- | --- | --- |
| hidden or visible state | visual, audio, text, motion, timing | what the player should believe | consequence they can anticipate | safe way to probe | feedback or recovery |

Rate each decision-critical rule:

- **Noticeable:** the relevant change can be perceived.
- **Attributable:** the player can connect it to a cause.
- **Predictable:** the rule supports a useful next-step forecast.
- **Consistent:** similar conditions produce explainable results.
- **Recoverable:** a mistaken model can be corrected without disproportionate cost.

Uncertainty is healthy when the player knows what is uncertain and can manage its risk. Confusion is unhealthy when the player cannot identify the governing variables.

## Worked Example: Tideglass Courier

### Intent

The player pilots a small salvage skiff between unstable islands. Each expedition should make route planning feel like a trade between reliable recovery and tempting cargo, while persistent upgrades open new route shapes rather than simply removing danger.

### Boundary

- Included: one expedition, return to harbor, and the upgrade choice before the next expedition.
- Excluded: detailed weather simulation, harbor politics, and other pilots.
- Inputs: forecast pattern and salvage-site layout.
- Outputs: recovered tideglass, damaged modules, and newly charted routes.
- Time scales: route leg, expedition, and several expeditions.

### Parts

| Part | State | Behavior | Visibility |
| --- | --- | --- | --- |
| Skiff | fuel, hull, cargo, modules | moves, salvages, returns | direct gauges and animation |
| Route leg | distance, current, hazard | consumes fuel, may damage hull | forecast plus uncertainty band |
| Salvage site | yield, volatility | converts time and risk into cargo | scan estimate |
| Harbor | stored tideglass, repair capacity | repairs and converts cargo into modules | direct |
| Module | effect, slot cost | alters sensing, capacity, or route handling | direct before selection |

### Core Loop

```text
scan route -> choose destination -> commit fuel -> resolve travel -> salvage or turn back -> read changed risk -> choose again
```

The "turn back" choice keeps the loop interactive after success; cargo is not automatically safe when collected.

### Meta Loop

```text
return with tideglass -> repair or build a module -> alter sensing/capacity/handling -> attempt a different route profile
```

Modules expand planning styles. A sensor narrows forecast uncertainty; a rack increases cargo but worsens fuel use; a keel reduces current penalties but occupies the sensor slot.

### Feedback Loops

Reinforcing path:

```text
successful routes -> more tideglass -> more route options -> access to richer sites -> more tideglass
```

Limits include module slots, rising route volatility, repair costs, and cargo drag. Without them, early success would erase route tension.

Balancing path:

```text
more cargo -> greater drag -> more fuel per leg -> smaller safe return margin -> pressure to stop salvaging
```

This brake is useful only if cargo drag and return cost are visible before another commitment.

### Minimal Equations

```text
leg_fuel = distance * current_factor * (1 + cargo / cargo_drag_scale)
hull_next = max(0, hull_now - hazard_damage)
safe_margin = fuel_now - estimated_return_fuel
```

The forecast may show an interval rather than an exact value, but the player must know why that interval exists.

### Prototype Question

"After two route legs, can a new player predict whether one more salvage stop leaves a credible return plan, and do different players make defensible choices?"

Prototype only the route map, fuel, cargo drag, forecast interval, and return decision. Defer art, crafting breadth, story, and module rarity.

## Model Verification

- Simulate or hand-trace at least one full cycle at minimum, typical, and maximum values.
- Confirm every stock has a source or initial value and every intended depletion has a sink.
- Confirm no required resource is available only after spending that same unavailable resource.
- Check conservation where intended: transfers should not create or destroy aggregate quantity accidentally.
- Mark all delayed relationships and evaluate at least twice the longest delay.
- Check whether a player can wait, hoard, loop, or reset to bypass the intended cost.
- Verify feedback at the point of commitment, the point of resolution, and the next decision.
- Re-check loop polarity after adding exceptions or conditional relationships.
