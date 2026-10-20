# Scale bench results (disposable spike, not production)

**Machine:** 2019 MBP, i7-8850H (6C/12T), Radeon Pro 560X (used by all three renderers; Intel UHD 630 never selected), macOS 15.8.1.
**Godot:** 4.7.2.stable (official editor binary, not an export template). Window 1366x1024 px (HiDPI off), VSync off, MSAA 2x.
**Scene:** 40x40 km, 256x256 terrain, sea plane, 1 km chunks, 4 mesh variants (apartment, balcony apartment, gable house, warehouse; ~12-24 tris),
per-instance colour + scale, one MultiMesh per (chunk, variant), per-chunk proxy mesh swapped in beyond 3 km (visibility_range, no fade).
Buildings sit on a 30 m grid inside 6 gaussian clusters; the 480k request saturated at 326,750 placed buildings.
**Method:** 60 warm-up + 180 measured frames per case; frame time = delta between `process_frame` ticks (full CPU+GPU frame). Raw data: `results/*.json`, screenshots: `results/shots/`.

## Render, shadows OFF: avg ms (p95) per camera preset; "Sh-on worst" = worst preset avg with sun shadows ON

| Renderer | Bldgs | metro | district | street | Sh-on worst | draw calls m/d/s |
|---|---|---|---|---|---|---|
| Compat | 10k | 4.6 (6.6) | 3.3 (4.5) | 2.9 (4.5) | 4.8 | 309/46/121 |
| Compat | 30k | 4.7 (6.1) | 3.6 (5.4) | 3.0 (4.7) | 6.9 | 354/51/137 |
| Compat | 60k | 9.8 (16.0) | 4.0 (10.9) | 5.1 (10.6) | 8.3 | 398/51/156 |
| Compat | 120k | 4.7 (5.4) | 3.9 (4.4) | 3.5 (4.5) | 5.9 | 431/52/166 |
| Compat | 240k | 9.0 (12.7) | 4.5 (9.6) | 5.2 (9.2) | 8.1 | 510/54/243 |
| Compat | 327k | 10.8 (16.7) | 4.7 (12.5) | 6.2 (12.1) | 12.9 | 579/54/291 |
| Mobile (Vulkan) | 10k / 60k / 240k | 4.2 / 3.7 / 4.1 | 3.1 / 3.0 / 3.3 | 3.3 / 8.3* / 3.2 | 8.3 / 4.3 / 4.8 | same as Compat |
| Fwd+ (Vulkan) | 10k / 60k / 240k | 6.1 / 5.6 / 6.4 | 5.5 / 5.5 / 6.2 | 4.1 / 3.8 / 4.8 | 7.2 / 7.7 / 8.8 | same as Compat |
| Compat, NO proxy LOD | 60k / 240k | 16.9 / 22.7 | 4.4 / 5.3 | not run | not run | 1313 / 1808 (metro) |
| Compat, detail range 10 km | 240k | 7.3 (10.8) | 5.5 (7.5) | 8.0 (10.4) | not run | 510/103/449 |

Mobile/Fwd+ p95 values are in the JSONs; Mobile p95 was 10-15 ms in shadows-off cases despite 3-4 ms averages (bimodal frame pacing, cause not investigated).
`*` single-case outlier. Memory (Compat): 46 -> 132 MB static, 64 -> 86 MB video from 10k to 327k. Mobile GPU time 1.5-4 ms, Fwd+ 3-8 ms (Compat GPU time is not exposed: reads 0).

## Simulation tick (headless, GDScript, `results/sim.json`, 3 reps of 100 ticks)

| Variant | ms/tick (3 reps) |
|---|---|
| Packed arrays, 60k parcels + 20k cohorts, serial | 68 / 74 / 77 |
| Same, WorkerThreadPool, 4 groups | 42 / 37 / 37 (about 1.8-2x) |
| 10k parcels + 3.3k cohorts: packed / RefCounted objects / Dictionaries | 11.0 / 36-39 / 41-45 (packed ~3.5x faster) |

Per tick: neighbour diffusion, investor feasibility per vacant parcel, relocation sampling of 4 candidates per cohort. Phase split at 60k serial: diffusion 48 ms, investor 15, relocation 3, apply 2.
**Determinism (100 ticks):** same seed twice = identical SHA-256 (serial and 4-thread); different seed differs; 4-thread hash equals serial hash. Holds because groups are fixed index ranges with per-group seeded RNGs, read-only shared inputs, per-group output slices and an ordered serial merge.

## Observations and problems
- Machine was noisy: background load average ranged 5-25 (Metal shader compiler, other sessions). A rerun of Compat 60k changed metro from 9.9 to 5.9 ms and street from 5.1 to 3.4 ms. Treat sub-2 ms differences as noise, and the 60k-vs-120k non-monotonic Compat rows as noise.
- Rare one-off stalls: 1007 ms (Fwd+ 30k, shadows on, first frames) and 771 ms (Mobile 10k, district, shadows on); likely shader/pipeline compilation on first shadow use.
- Metro is the worst preset: it is CPU-bound by ~400-580 per-chunk proxy draw calls plus culling ~2k MultiMeshes; cost grows with populated chunk count, not building count. Without proxy LOD metro is 17 ms at 60k and 23 ms at 240k (4.2M tris, 1.8k draws).
- Street/district cost is set by the 3 km detail radius, not by N: 244-345 draw calls at 327k. Raising the radius to 10 km raises street cost from 5.2 to 8.0 ms (240k).
- Shadows ON add about 1-3 ms (more in district/street where 600-880k tris are shadow-cast); still well inside budget here.
- Compat and Vulkan renderers look different with identical scene values (Mobile/Fwd+ render noticeably paler: colour pipeline and tonemapping differ). Art calibration must target the chosen renderer.
- Proxy swap is a hard pop (no fade); proxies are flat slabs that read poorly in district view. Visual LOD quality was not judged.
- GDScript scene build is slow at scale (1.2 s at 60k, 10 s at 240k, 78 s at 327k); a real game would build/stream incrementally.
- An early batch attempt hung because a zsh variable was not word-split (Godot opened its project manager); rerun fixed. No renderer failed to start.

## Conclusion
On this Intel Mac with a Radeon 560X, a static 40 km region with up to ~327k low-poly buildings (about 20 tris each) rendered at >= 77 fps in the worst case (every case <= 13 ms avg, p95 <= 17 ms; most 150-340 fps) in all three renderers, given chunked MultiMeshes + a distance proxy LOD with a 3 km detail radius. By these numbers Compat comfortably holds 60 fps (and mostly 120+) up to the 327k tested; the metro view with p95 ~16-17 ms is the first thing to hit the 60 fps edge, and a second LOD tier (merged super-chunk proxies) would be the first fix. 30 fps is not a concern at any tested N.
The sim side is the tighter limit: a 60k-parcel tick costs ~70 ms serial / ~40 ms on 4 threads in GDScript with packed arrays, fine for a daily tick, not for per-frame work, and it is deterministic.

## What this does NOT prove
- Any iPad performance (different GPU, tile-based, thermal limits, Metal via Godot's iOS renderer); an Intel Mac with a discrete AMD GPU is not the target device.
- Real game load: no roads, trees, props, textures, UI, particles, animation, construction transitions, picking, or per-frame instance updates; all buildings are static and unoccluded by design (no occlusion culling).
- Real mesh complexity (these are 12-24 tris), real city layout (30 m grid, gaps between all buildings) or overdraw.
- Streaming, load times, save/load, memory on 3-4 GB iPads, or sim+render running together (render ran with no sim, sim ran headless).
- Export-template speed: GDScript here ran in the editor binary; release templates are likely faster.
- Variance bounds: 1 run per case (plus one 60k rerun); the machine was under external load.
