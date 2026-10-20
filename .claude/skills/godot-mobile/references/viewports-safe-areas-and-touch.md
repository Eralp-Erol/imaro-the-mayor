# Viewports, Safe Areas, and Touch

Design against logical content space, physical screen constraints, and input coordinate space as separate concerns.

## Choose the Content Model

Before setting a base size, answer:

- Is the game primarily 2D, 3D, pixel art, or UI?
- Must the camera reveal more world on wider or taller screens, or must composition remain fixed?
- Is portrait, landscape, or sensor rotation supported?
- What is the smallest supported physical screen and UI scale?
- Do tablets and foldables receive more content, larger spacing, or a different region arrangement?
- Is low-resolution rendering an art requirement or a performance option?

Use one design size as an authoring coordinate system, not as a promise that every device has the same shape or density.

## Stretch Strategies

### Canvas Items

`canvas_items` scales 2D layout from the base size while rendering at the target resolution. It is a strong default for vector-like 2D, fonts, and normal mobile UI. Bitmap art can still show filtering or downsampling artifacts, so inspect imports.

### Viewport

`viewport` renders the root viewport at its base size and scales the result. It can preserve a low-resolution pixel canvas and can lower GPU cost, but the whole rendered result may become soft or pixelated. Keep critical UI in a separate higher-resolution path if the project design and exact version support it.

### Aspect

- `expand` reveals more width or height depending on the device.
- `keep_width` preserves width and may reveal more vertically.
- `keep_height` preserves height and may reveal more horizontally.
- `keep` preserves the designed aspect and introduces bars when needed.
- `ignore` fills the screen non-uniformly and is rarely correct for authored visuals.

Verify the exact setting names in the inspected Godot version. Test game embedding in the editor with viewport resizing configured to match standalone behavior.

## Safe Area

Keep decorative backgrounds full bleed. Inset controls whose loss or obstruction matters: navigation, purchases, pause, text entry, primary actions, and status values.

This example converts the platform safe rectangle from screen coordinates into root viewport coordinates, then applies margins. Use it only after verifying the exact release API and the project's stretch transform. Attach it to the critical-content `MarginContainer`, not the background.

```gdscript
extends MarginContainer

func _ready() -> void:
    get_viewport().size_changed.connect(_apply_safe_area)
    _apply_safe_area()

func _apply_safe_area() -> void:
    if not OS.has_feature("mobile"):
        return

    var safe_screen: Rect2i = DisplayServer.get_display_safe_area()
    var screen_to_viewport: Transform2D = (
        get_viewport().get_screen_transform().affine_inverse()
    )
    var safe_start: Vector2 = screen_to_viewport * Vector2(safe_screen.position)
    var safe_end: Vector2 = screen_to_viewport * Vector2(safe_screen.end)
    var viewport_size: Vector2 = get_viewport_rect().size

    add_theme_constant_override(&"margin_left", maxi(0, roundi(safe_start.x)))
    add_theme_constant_override(&"margin_top", maxi(0, roundi(safe_start.y)))
    add_theme_constant_override(
        &"margin_right", maxi(0, roundi(viewport_size.x - safe_end.x))
    )
    add_theme_constant_override(
        &"margin_bottom", maxi(0, roundi(viewport_size.y - safe_end.y))
    )
```

Retest after orientation changes, split-screen/multi-window changes, and fold posture changes where supported. On desktop, safe-area fallback behavior differs, so use explicit preview fixtures rather than trusting the mobile branch.

## Touch Architecture

Use three layers:

1. **Platform event:** `InputEventScreenTouch`, `InputEventScreenDrag`, standard `Control`, or `TouchScreenButton`.
2. **Gesture or action mapping:** tap, drag, aim, pinch, hold, or an Input Map action.
3. **Gameplay command:** jump, move, place, select, pause, or camera look.

Gameplay should consume commands, not know whether a finger, mouse, keyboard, or gamepad produced them.

Use visible controls for actions players must find and repeat. Use world gestures when direct manipulation is clearer. Avoid invisible edge gestures that conflict with operating-system navigation.

## Touch Rules

- Track contacts by `index` from press through release or cancellation behavior.
- Distinguish a tap from a drag using distance and, if needed, duration thresholds.
- Apply thresholds in a stable logical coordinate space and account for content/UI scale.
- Do not require pixel-perfect finger placement.
- Give immediate visual or audio feedback on press and a clear result on release.
- Decide whether dragging continues after the finger leaves the original control.
- Resolve conflicts between scrolling, dragging, camera look, and button activation explicitly.
- Let GUI controls consume input before world-level `_unhandled_input` logic.
- Avoid triggering important destructive actions on touch-down when cancellation on drag-out is expected.

## Input Emulation

Godot can emulate touch from mouse for desktop testing and mouse from touch for compatibility. Inspect the project settings and choose one intended path.

- Do not process native touch and its synthetic mouse event as two independent actions.
- Desktop emulation does not reproduce multi-touch, palm behavior, OS edge gestures, device latency, density, or touch cancellation.
- Use a physical device before accepting any gesture implementation.

## Virtual Keyboard and Forms

- Use `LineEdit` or `TextEdit` so the platform keyboard, selection, clipboard, and IME can work.
- Choose an appropriate virtual keyboard type for number, decimal, email, URL, phone, or password entry when available in the exact version.
- Keep the focused field and validation message visible when the keyboard changes usable space.
- Do not strip text on every keystroke in a way that breaks composition, paste, caret, or locale-specific decimal entry.
- Provide explicit next, submit, and cancel behavior.
- Test hardware keyboard attachment as well as the software keyboard.

## Orientation and Camera

For sensor rotation, design a real relayout. Rotating a fixed landscape canvas into portrait is not responsive design.

- Recompute safe area and breakpoint layout after orientation changes.
- Preserve game state and current focus.
- Ensure camera limits and field of view still expose required gameplay content.
- Decide whether an in-progress gesture is canceled on rotation.
- Test rotation while a modal, keyboard, video, or pause screen is active.

## Device Matrix

Include at least:

- Narrow phone.
- Tall phone with display cutout.
- Wide landscape phone with system gesture areas.
- Small and large tablet-like windows.
- A foldable-like near-square window if in scope.
- Minimum and maximum supported UI scale.
- Supported orientation changes.
- External keyboard or controller if supported.
