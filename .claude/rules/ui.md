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
- Input/UI profiles (ADR-0004): desktop primary (mouse/keyboard/trackpad, hover allowed), touch profile secondary (≥ 44 pt targets, safe areas, no hover-only info). UI consumes input before the world camera.
- Strings centralised. Currency OPEN (Q-003): name/symbol only from config, placeholder `¤`, never ₺ or an invented name. Never copy UI/labels/numbers from concept images (VIS-07).
