---
paths:
  - "src/ui/**"
  - "scenes/ui/**"
  - "**/*theme*.tres"
---
# Game UI rules

- Only real simulation data; no placeholder figures, dead buttons, or tabs for unbuilt systems (hide or label honestly).
- Mayor verbs only (zoning, public works, budget, policy). No "place private building" tools (CAN-03).
- Show causal reasons recorded by the simulation (SIM-12); never a single happiness % (SIM-09).
- Touch targets ≥ 44 pt equivalent, safe areas respected, UI consumes input before the world camera; mouse/trackpad equivalents.
- Strings centralised (language/currency for Anderva pending Q-003). Never copy UI/labels/numbers from concept images (VIS-07).
