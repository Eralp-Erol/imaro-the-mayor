---
name: sim-invariants
description: Rules, patterns and test recipes for Imaro's deterministic simulation — fixed-tick game time independent of frame rate, seeded per-system RNG streams, integer money, command-based player input, autonomous actors with recorded reasons, save/load round-trips with state hashes, and the canon invariants that must hold as automated tests (no municipal spawning of private buildings, no single happiness score, development takes time and can fail). Use when designing, implementing, reviewing or testing any simulation, economy, actor, politics, time or save code, or when a test is flaky/non-deterministic.
---

# Simulation invariants

The simulation is a pure model: `state(t+1) = tick(state(t), commands(t))`. Rendering, UI and input only read snapshots/events and submit commands.

## Architecture rules (TEK-01, TEK-02)
1. **Purity.** Simulation classes extend `RefCounted` (or are plain data); no `Node`, `SceneTree`, signals to scene nodes, `Time`, `OS`, file I/O inside tick logic, `randf()/randi()` globals, or `Engine.get_frames_*`.
2. **Time.** A tick is a fixed unit of game time. The view accumulates real time × speed and calls `tick()` an integer number of times; tick logic never sees `delta`. Pause = zero ticks.
3. **Randomness.** One `RandomNumberGenerator` per system (investors, households, politics…), seeded from the world seed + a fixed stream id, stored in state (seed + state) so save/load resumes the exact sequence. Never share a stream across systems (adding a call in one would shift another).
4. **Numbers.** Money in integer minor units (kuruş-like) or fixed-point ints; avoid float accumulation in persistent state. Floats are fine for transient scoring if results are rounded deterministically before being stored.
5. **Iteration order.** Iterate arrays by index or sorted ids — never rely on Dictionary insertion order created from unordered sources, never iterate scene-tree order.
6. **Commands.** Player actions are command objects (`ProposeZoning`, `BuildRoad`, `SetBudget`…) validated and applied at a tick boundary; they are loggable and replayable.
7. **Reasons.** Every actor decision stores a compact reason record (`{actor, decision, factors{...}, threshold}`) for UI explanation (SIM-12) and for tests.
8. **Data-oriented at scale.** Large populations (parcels, households) live in Packed*Array columns indexed by id; aggregate/cohort models where individuals are not visible (ADR-0002, benchmark in `experiments/scale-bench/RESULTS.md`).

## Canon invariants → tests (must exist once the related system exists)
| Invariant | REQ | Test recipe |
|---|---|---|
| Municipality cannot create private buildings | CAN-03 | Apply every municipal command type on vacant private parcels; assert no private development appears without an actor decision record. |
| Development takes time and can fail | SIM-07 | Positive scenario reaches construction→completion over N ticks; negative scenario (high cost/low demand) yields "no investment" with a recorded reason. |
| Infrastructure ≠ automatic building | SIM-07 | Build road/utility to empty land with no demand; assert no development within horizon. |
| No single popularity score | SIM-09 | Political state exposes ≥2 independent group stances; a decision can move them in opposite directions. |
| Divergence | SIM-10 | Two command scripts from the same seed produce measurably different land-use mixes after N ticks. |
| Other districts evolve off-screen | WLD-11 | Ticking with the player focused on one district changes state elsewhere. |

## Determinism & save tests (always)
- **Same seed ⇒ same hash:** run K ticks twice with identical command logs; compare a canonical state hash (serialize state with sorted keys → `hash()`/SHA-256).
- **Different seed ⇒ different hash** (guards against an unused seed).
- **Frame independence:** feed the tick driver different frame-delta sequences totalling the same game time; final hash identical.
- **Save round-trip:** run K ticks → save → load → run M ticks; hash equals the uninterrupted K+M run.
- **Thread safety (if WorkerThreadPool used):** parallel and serial tick produce the same hash.

## Review checklist
- [ ] No forbidden APIs in simulation files (`rg -n "randf\(|randi\(|Time\.|OS\.|get_tree|Node\b" <sim dir>`).
- [ ] New state fields included in serialization and in the hash.
- [ ] New tunable numbers live in config/data with a comment on their purpose.
- [ ] Each new actor decision records a reason; each new player verb is a command.
- [ ] Positive and negative scenario tests exist for new behaviour.
