---
paths:
  - "**/*.gd"
---
# GDScript (Godot 4.7.2) — adapted from claude-code-game-studios (MIT)

- Static typing everywhere: variables, parameters, return types, typed arrays (`Array[Parcel]`), typed signals. Godot warnings for untyped code stay enabled.
- Naming: `PascalCase` classes (`class_name` matches file `snake_case.gd`), `snake_case` funcs/vars, `SCREAMING_SNAKE_CASE` constants/enum values, `_private` members, signals past tense (`zoning_changed`).
- File order: class_name/extends → constants/enums → signals → @export → public vars → private vars → @onready → built-ins → public methods → private methods → `_on_*` callbacks.
- Signals go up, method calls go down; connect in code, not the editor; no signals for request/response.
- Cache node refs with `@onready`/`%Unique`; never `get_node()`/`$` in `_process`. Disable `_process` when idle. Use `StringName` (`&"id"`) for hot comparisons.
- Data: typed `Resource` subclasses or RefCounted classes over loose Dictionaries for structured data; Packed*Array columns for large populations.
- Autoloads only for truly global services; never hold scene node refs in them.
- GDExtension only with profiler evidence (ADR-0002).
- No Godot 3 syntax (`yield`, string `connect`). Check `docs/engine-reference/godot/deprecated-apis.md` when unsure; mark unverified APIs.
- ripgrep: no `gdscript` type — use `--glob '*.gd'`.
- Simulation code has extra rules: `.claude/rules/simulation.md`.
