---
name: visual-gate
description: Imaro's visual quality gate — captures real Godot frames at standard camera presets, compares them with the approved references and the previous accepted captures, and judges them against the art-direction checklist (low-key low-poly, layered Aegean fabric, scale sanity, single world across zooms, density restraint, rejected aesthetics). Use for any change a player can see (world, buildings, terrain, lighting, camera, HUD look), before calling such work done, and when the user asks whether something "looks right". Never judge visuals from code or descriptions alone.
---

# Visual gate

## 1. Capture (evidence first)
- Use `tools/capture.sh <name> [--resolution WxH] [-- <game args>]` (see `tools/README.md`). Standard presets once the production camera exists: `metro` (whole Ismeral), `district` (~2 km), `street` (~200 m) and, when relevant, `country`. Until presets exist, record the exact camera args used so captures are repeatable.
- Same preset before/after for any change. Store under `artifacts/screenshots/` and reference paths in the task file.
- **Open and look at every image you judge** (Read the PNG). A black/empty/partial frame is a failed capture, not a visual result.
- Video when motion matters (construction progress, camera transitions): Godot Movie Maker `--write-movie out.avi --fixed-fps 30 --quit-after N`.

## 2. Compare
- Regression: `tools/visual-diff.sh before.png after.png diff.png` — report % changed pixels; inspect the diff image where it changed.
- Direction: compare with `design/foundation/visual-references/` (metro/country scale). References are direction, not pixel targets; runtime must be *simpler*.

## 3. Checklist (answer each with evidence: image path + what you see)
1. F04-Q1: Reads as an original contemporary city fed by İzmir — a real mixed metropolis, not a resort or a generic US downtown?
2. F04-Q2: T0 is a working city open to growth, not an empty town; D1+D6 read as the core? (when the metro exists)
3. F04-Q3: Port/industry on the mainland west of D4; no T0 major industry on islands? (WLD-03)
4. F04-Q4: Mix of old/mid-century/new stock, public life, industry, housing, commerce, agriculture?
5. F04-Q5: Does the presentation leave room for the city to grow in other directions (no baked-in future)?
6. F04-Q6: Do country/metro/district/street views come from the **same** 3D geography with the same art grammar? (WLD-01)
7. Scale: clock tower vs 4–5 floor blocks; trees, vehicles, people, street widths plausible (VIS-03, WLD-07).
8. Style: matte flat-shaded low-poly, restrained detail, readable silhouettes; NOT voxel-everything, NOT hyperreal, NOT toy-saturated (VIS-01, VIS-05).
9. Density restraint: decoration does not fill every surface; the playable information (parcels, roads, construction, problems) is readable at game zoom.
10. Light: plain daylight default with soft shadows; overcast/rain alternative possible; golden hour not default.
11. HUD (if visible): real data only, Turkish, does not bury the city, no concept-image UI copied (VIS-07).
12. Repetition: is the same block/facade obviously repeated? Do districts differ in character?

## 4. Verdict
`PASS` / `PASS WITH FIXES` / `FAIL` / `NO EVIDENCE`, then findings: image path → issue → rule → concrete fix. If the whole composition is wrong (e.g. generic box grid), say FAIL and recommend rebuilding geometry/composition rather than cosmetic fixes. Record the verdict and image paths in the task file.
