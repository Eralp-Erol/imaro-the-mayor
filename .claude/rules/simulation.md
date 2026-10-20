---
paths:
  - "src/sim/**"
  - "src/simulation/**"
  - "tests/**/sim*"
---
# Simulation code (TEK-01/02, CAN-03) — full rationale in the `sim-invariants` skill

- Pure logic: RefCounted/plain data only. Forbidden here: `Node`, `get_tree()`, `Time.*`, `OS.*`, global `randf()/randi()/randomize()`, `Engine.get_frames_*`, rendering/input classes, file I/O inside tick.
- Fixed tick; tick code never receives `delta`. Seeded per-system `RandomNumberGenerator` stored in state.
- Money/persistent quantities as ints (fixed-point). Deterministic iteration order (index/sorted ids).
- Player input = command objects applied at tick boundaries. Municipal commands never create private buildings; only actor decisions do, and each decision records its reason.
- New state ⇒ serialized + hashed + covered by determinism/save round-trip tests.
- Tunable numbers in config/data, not scattered literals.
