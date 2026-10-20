---
paths:
  - "**/*.tscn"
  - "**/*.tres"
  - "**/*.uid"
---
# Scene/resource text files — adapted from claude-code-game-studios (MIT)

Prefer generating/modifying scenes from code or the editor. When hand-editing:
- Never change the `format=` header value; never reuse an `ext_resource`/`sub_resource` id in a file.
- Never copy a node block with its `unique_id=`; never invent `uid://` values (omit `uid=`, let import assign).
- Never edit/delete `.uid` files; move them with their script/shader; commit them.
- After any hand edit: `tools/godot.sh --headless --path . --editor --import --quit`, then run the scene once (or `tools/verify.sh quick`) and check for load errors.
