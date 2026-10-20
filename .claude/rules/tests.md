---
paths:
  - "tests/**"
---
# Tests

- Tests must be able to fail: assert concrete values/invariants, not just "no crash". Include a negative case for behaviour.
- Headless tests (`--headless`) for logic; rendering/screenshot checks need a windowed run (dummy renderer cannot capture).
- Deterministic: fixed seeds, no wall-clock dependence; simulation tests drive `tick()` directly.
- Tests exit non-zero on failure and print a one-line summary `<SUITE>: x/y passed`.
- Name tests by the behaviour/REQ they protect (e.g. `test_municipal_command_never_spawns_private_building`).
