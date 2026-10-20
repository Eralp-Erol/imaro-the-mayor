---
name: godot-mobile
description: "Builds and prepares Godot 4.x mobile games for Android and iOS, covering viewport scaling, orientation, safe areas, touch and gestures, virtual keyboards, lifecycle, device profiling, mobile rendering, texture memory, and signed exports. Use when requests mention phones, tablets, touch input, mobile performance, Android, iOS, APK, AAB, Xcode, or store builds."
license: MIT
metadata:
  author: godot-skills
  version: "1.0.0"
---

# Godot Mobile

Treat mobile as a target with variable screens, interruptible lifecycle, constrained CPU/GPU/memory/thermal budgets, and platform-specific release pipelines. A desktop preview is useful but never sufficient evidence.

## Inspect Before Editing

Scale this inspection to the change's risk, and complete the relevant checks before changing gameplay, project settings, import options, or export presets.

1. Locate `project.godot`, confirm the root, and read `config/features`, exact rendering method and driver, base viewport size, stretch mode and aspect, orientation, physics tick rate, input emulation settings, texture defaults, application identity, and main scene.
2. Run the project's established Godot executable with `--version` when available. Match editor, export templates, APIs, and platform documentation to that exact Godot 4.x release.
3. Inspect existing scenes and typed GDScript conventions, especially input routing, pause/state ownership, spawned-node lifecycle, UI anchors and containers, camera behavior, quality settings, save paths, and app lifecycle handling.
4. Inspect `export_presets.cfg` without exposing credentials. Record Android package name, version code/name, architectures, permissions, renderer, build format, and iOS bundle ID, team/capabilities, orientation, icons, and signing expectations.
5. Inspect texture, audio, model, shader, particle, and font imports. Identify the largest resources and features likely to dominate memory, bandwidth, overdraw, or package size.
6. Run a baseline on at least one representative physical device if available. Capture frame time, frame pacing, memory, startup, input latency, orientation, safe-area layout, suspend/resume, and thermal behavior.

Do not change renderer, stretch mode, orientation, compression, package identity, permissions, or signing fields without explaining the project-wide and release impact.

## Mobile Workflow

1. Define the supported device matrix: Android/iOS versions, phone/tablet/foldable, portrait/landscape, minimum hardware, target frame rate, renderer, and store or sideload distribution.
2. Choose a base viewport and stretch strategy from the content. Use responsive `Control` anchors and containers for UI; do not author separate layouts for every resolution.
3. Protect critical controls from display cutouts and rounded corners. Re-evaluate safe area after orientation or window changes.
4. Define input semantics before gestures. Prefer large standard controls or `TouchScreenButton` for visible actions, and centralize raw touch recognition for world gestures.
5. Keep physics and gameplay device-agnostic by translating touch, mouse, keyboard, and gamepad into the same actions or commands.
6. Set a frame-time and memory budget. Profile on device, identify whether the bottleneck is CPU, GPU, memory, loading, or thermal throttling, then change one measured cause.
7. Handle app pause, resume, focus loss, audio interruptions, rotation, virtual keyboard, and safe saving.
8. Configure export templates and platform toolchains for the exact editor version. Keep signing credentials outside version-controlled presets.
9. Produce debug device builds early and a release-signed build before considering the pipeline complete.

## Viewport Decisions

- Use `canvas_items` for most high-resolution 2D/mobile UI that should render at device resolution while scaling from a design size.
- Use `viewport` when the project deliberately renders at a fixed low base resolution, such as pixel art or a measured lower-resolution performance strategy.
- Use `expand`, `keep_width`, `keep_height`, or `keep` based on what content may become visible or letterboxed. Never choose by name alone; test the supported aspect range.
- For 3D, choose the camera keep-aspect mode that preserves the important field of view in the intended orientation.
- Keep UI independent from 3D resolution scaling when the project/version supports it, so performance reduction does not make text unreadable.

## Typed Touch Example

This recognizer handles native touch only. UI controls consume their events first because the code uses `_unhandled_input`. For desktop testing, enable the project's mouse-to-touch emulation rather than adding a second mouse branch that may fire twice on device.

```gdscript
extends Node

signal tapped(viewport_position: Vector2)
signal dragged(touch_index: int, relative_motion: Vector2)

@export_range(1.0, 128.0, 1.0) var tap_slop: float = 24.0
var _touch_origins: Dictionary = {}
var _touch_exceeded_slop: Dictionary = {}

func _unhandled_input(event: InputEvent) -> void:
    var touch: InputEventScreenTouch = event as InputEventScreenTouch
    if touch != null:
        if touch.pressed:
            _touch_origins[touch.index] = touch.position
            _touch_exceeded_slop[touch.index] = false
        else:
            if not _touch_origins.has(touch.index):
                return
            var origin: Vector2 = _touch_origins[touch.index] as Vector2
            var exceeded_slop: bool = bool(_touch_exceeded_slop[touch.index])
            var is_tap: bool = (
                not touch.canceled
                and not exceeded_slop
                and origin.distance_to(touch.position) <= tap_slop
            )
            if is_tap:
                tapped.emit(touch.position)
            _touch_origins.erase(touch.index)
            _touch_exceeded_slop.erase(touch.index)
        return

    var drag: InputEventScreenDrag = event as InputEventScreenDrag
    if drag != null and _touch_origins.has(drag.index):
        var origin: Vector2 = _touch_origins[drag.index] as Vector2
        if origin.distance_to(drag.position) > tap_slop:
            _touch_exceeded_slop[drag.index] = true
        dragged.emit(drag.index, drag.relative)
```

Scale gesture thresholds for the project's viewport coordinate space and UI
scale. Track each touch by `index`; never assume only finger zero exists. Clear
tracked touches when the application loses focus or the owning gameplay state
is interrupted.

## Performance Priorities

- Profile first on target-class devices and inspect frame time, not only FPS averages.
- Keep inactive nodes from processing. Free or recycle spawned content after it leaves its useful lifetime.
- Reduce transparent overlap, full-screen effects, expensive particles, shadowed lights, shader texture reads, and unnecessary render targets when GPU-bound.
- Reuse materials, meshes, and textures. Use LOD, visibility ranges, simplified collision, and measured resolution scaling for 3D.
- Import textures at justified dimensions with platform-appropriate VRAM compression. Check artifacts and memory on both Android and iOS targets.
- Stream or load large content away from latency-sensitive interaction. Avoid a first-use shader or resource stall during play.
- Pool only when profiling shows allocation, instantiation, or cleanup spikes; a bounded `queue_free()` lifecycle is simpler when adequate.
- Test long enough to expose heat, clock throttling, battery drain, and memory growth.

## Verification

- Parse/import with the matching editor and run existing tests. Use `<godot> --headless --path <project> --editor --quit` when supported, but do not treat it as device validation.
- Test minimum, design, ultrawide, tablet, and foldable-like aspect ratios in every supported orientation.
- Verify cutouts, rounded corners, system bars, gesture areas, virtual keyboard, and rotation while forms or gameplay are active.
- Test single tap, long press, drag, swipe, multi-touch, interrupted gestures, edge gestures, and UI-over-gameplay event consumption.
- Compare 30/60/90/120 Hz devices or simulated frame caps where applicable. Confirm physics and gesture behavior remain time-based.
- Capture CPU and GPU frame time, draw calls, object count, memory, texture memory, and spikes in a representative level on device.
- Run a sustained session, background and resume repeatedly, lock/unlock, accept a simulated interruption, and verify audio, timers, networking, and save state recover.
- Build and install an Android debug package early. Before release, produce the required store artifact with release signing and test the exact artifact.
- Export iOS from macOS with the required Xcode/signing setup, then test a physical device. Simulator success is not device success.
- Verify app name, icon variants, orientation, package/bundle identity, versioning, permissions, privacy declarations, architectures, and release mode.
- Report tested devices, OS versions, renderer, build type, measurements, and any store/signing checks that remain external.

## Pitfalls

- Designing only for one phone screenshot or treating resolution as physical size.
- Stretching with aspect ignore and distorting gameplay or touch geometry.
- Pinning important controls to screen edges without accounting for safe area.
- Handling both touch and emulated mouse events, causing duplicate actions.
- Polling a single global touch position and breaking multi-touch or interrupted gestures.
- Using tiny icon-only targets with no persistent label or feedback.
- Optimizing desktop measurements instead of the slowest supported device.
- Leaving off-screen enemies, effects, timers, audio players, or `_process` callbacks alive indefinitely.
- Enabling desktop-grade post-processing, shadows, or transparent effects without mobile GPU profiling.
- Changing texture compression globally without checking alpha, artifacts, source size, and target support.
- Assuming pause or focus loss automatically saves state and stops every relevant subsystem.
- Committing keystores, passwords, provisioning data, API secrets, or generated credential files.
- Following toolchain versions from generic advice instead of documentation for the exact Godot release.

## References

- [Viewports, safe areas, and touch](references/viewports-safe-areas-and-touch.md)
- [Performance and lifecycle](references/performance-and-lifecycle.md)
- [Android and iOS export](references/android-and-ios-export.md)
