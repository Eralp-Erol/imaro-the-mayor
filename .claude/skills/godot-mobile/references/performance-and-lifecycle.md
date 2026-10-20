# Performance and Lifecycle

Optimize from measurements captured in an exported build on target-class hardware. Mobile bottlenecks vary sharply by GPU, driver, thermal state, OS, and scene.

## Establish Budgets

Frame-time targets are more actionable than FPS labels:

- 60 FPS allows about 16.7 ms for a frame.
- 30 FPS allows about 33.3 ms for a frame.
- Higher refresh targets reduce the budget proportionally.

Define budgets for CPU frame time, GPU frame time, peak memory, texture memory, startup, level transition, package size, and sustained heat. Include headroom for slower devices and OS activity.

## Measurement Loop

1. Reproduce in a representative scene and exported build.
2. Capture frame timeline, CPU functions, renderer counters, memory, node/object counts, and spikes.
3. Determine whether the limit is CPU, GPU, allocation/loading, memory pressure, or thermal throttling.
4. Change one likely cause.
5. Capture the same workload again.
6. Keep the change only when the measurement and visual result justify it.

Do not compare unlike camera views, quality settings, warm-up states, or thermal conditions.

## CPU and Scene Tree

- Disable `_process`, `_physics_process`, input, timers, and animation for inactive content.
- Keep spawned content bounded. Free or recycle projectiles, enemies, particles, decals, audio players, and effects after their useful lifetime.
- Avoid repeated tree searches, resource loads, parsing, or allocation in hot callbacks.
- Use signals or events for infrequent changes instead of polling every frame.
- Simplify collision shapes and reduce active physics bodies when physics is measured as the bottleneck.
- Preserve the default physics tick for responsive real-time play unless measurement, interpolation, and input-latency testing support a change.
- Move heavy non-SceneTree data processing off the main thread only with a thread-safe design; scene nodes are not generally free-threaded.

Bounded cleanup can be simple:

```gdscript
extends Node2D

@export_range(0.1, 60.0, 0.1) var maximum_lifetime: float = 10.0
var _remaining_lifetime: float

func _ready() -> void:
    _remaining_lifetime = maximum_lifetime

func _process(delta: float) -> void:
    _remaining_lifetime -= delta
    if _remaining_lifetime <= 0.0:
        queue_free()
```

For large populations, central lifecycle management or pooling may reduce per-node callback cost. Prove it with profiling before adding that complexity.

## GPU

- Choose the renderer from target support and measured feature needs.
- Reduce full-screen transparency, particle overlap, layered UI blur, decals, and other overdraw.
- Keep mobile shaders simple and reduce texture samples.
- Limit dynamic shadow-casting lights, shadow distance, and shadow resolution.
- Use LOD and visibility ranges so tiny distant objects do not retain full geometry and shader cost.
- Reuse materials and shader configurations to reduce state changes.
- Measure post-processing, screen-space effects, reflection probes, GI, viewport textures, and procedural skies individually.
- Use 3D resolution scaling when GPU fill cost is the measured problem and UI clarity can remain independent.

Changing window or 3D render scale is a useful diagnostic: a large timing improvement points toward pixel/fill cost, while little change suggests another bottleneck.

## Assets and Memory

- Resize source textures to justified maximum display size.
- Select target-supported VRAM compression and inspect artifacts, especially alpha and UI assets.
- Use mipmaps where minification quality and sampling justify their added memory.
- Avoid loading every level, skin, audio track, and localization asset at startup.
- Stream longer audio when appropriate; keep short latency-critical effects readily available.
- Reuse meshes, materials, animation libraries, and immutable resources.
- Watch peak memory during transitions, where old and new scenes may coexist briefly.
- Test low-memory termination and recovery expectations for each platform.

## Frame Pacing and Stalls

A stable average can hide poor interaction.

- Capture long frames and correlate them with instantiation, shader compilation, resource loading, garbage/refcount cleanup, saves, networking, and scene changes.
- Warm required shaders or content before latency-sensitive play when supported by the project architecture.
- Spread noncritical work across frames only when doing so does not create inconsistent state.
- Avoid synchronous persistence or large parsing during touch response.
- Verify frame pacing with the final display mode and V-Sync configuration.

## Application Lifecycle

Inspect the exact Godot 4.x notification names and platform behavior before implementation. The owning app state should respond to application pause/resume and focus changes.

On pause or interruption:

- Save small critical progress promptly and handle write errors.
- Pause gameplay timers and input through one state owner.
- Stop or duck audio as product/platform policy requires.
- Suspend expensive networking, sensors, or background work when appropriate.
- Cancel or preserve active touches explicitly.
- Record enough state to recover if the OS terminates the process instead of resuming it.

On resume:

- Revalidate elapsed time, network/session state, and device resources.
- Restore audio and gameplay only when the user can see and control the app.
- Recompute viewport, safe area, orientation, and virtual-keyboard layout.
- Avoid applying a large unbounded `delta` to gameplay simulation.

Test home/background, lock/unlock, incoming interruptions, audio route changes, rotation, and process termination. The editor cannot model all of these accurately.

## Thermal and Battery Soak

Run representative gameplay for at least long enough to reach steady device temperature.

Record:

- Initial and sustained frame time.
- CPU/GPU clock or thermal warnings when tools expose them.
- Battery drain and charging state.
- Surface temperature observations.
- Memory trend and object count.
- Whether adaptive quality or a lower frame target activates.

A configuration that holds 60 FPS for two minutes and falls to 35 FPS after heating is not a stable 60 FPS configuration.

## Regression Checklist

- Cold start and warm start.
- First use of each major effect or scene.
- Long session with repeated spawn/despawn cycles.
- Rapid scene transitions.
- Pause/resume and process recreation.
- Low and high refresh displays.
- Lowest supported device and at least one different GPU family.
- Debug versus release build.
- Battery power versus charging if thermal behavior differs.
