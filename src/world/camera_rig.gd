class_name CityCamera
extends Node3D

signal parcel_tapped(screen: Vector2)
var camera := Camera3D.new()
var target := Vector3(-8, 0, 2)
var yaw: float = 0.55
var zoom: float = 105.0
var desired_zoom: float = 105.0
var pressed := false
var dragged := false
var start := Vector2.ZERO
var touches: Dictionary = {}
var touch_consumed := false

func _ready() -> void:
	add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.2
	camera.far = 600
	camera.current = true
	get_viewport().size_changed.connect(reset_gestures)
	apply_pose()

func reset_gestures() -> void:
	pressed = false
	dragged = false
	touches.clear()
	touch_consumed = true

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		reset_gestures()

func _process(delta: float) -> void:
	zoom = lerpf(zoom, desired_zoom, 1.0 - exp(-12.0 * delta))
	apply_pose()

func apply_pose() -> void:
	camera.position = target + Vector3(sin(yaw) * 105, 80, cos(yaw) * 105)
	camera.look_at(target)
	camera.size = zoom

func rotate_view(direction: float) -> void:
	yaw += direction * PI / 4.0
	apply_pose()

func focus(point: Vector3, close: bool = true) -> void:
	target = point
	desired_zoom = 45 if close else 105

func ground_at(screen: Vector2) -> Variant:
	return Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func pan(from: Vector2, to: Vector2) -> void:
	var a: Variant = ground_at(from)
	var b: Variant = ground_at(to)
	if a != null and b != null:
		target += a - b
		target.x = clampf(target.x, -55, 55)
		target.z = clampf(target.z, -48, 48)
		apply_pose()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed: desired_zoom = maxf(28, desired_zoom / 1.12)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed: desired_zoom = minf(135, desired_zoom * 1.12)
		if event.button_index == MOUSE_BUTTON_LEFT:
			pressed = event.pressed
			if pressed:
				start = event.position
				dragged = false
			elif not dragged:
				var point: Variant = ground_at(event.position)
				if point != null: parcel_tapped.emit(event.position)
	elif event is InputEventMouseMotion:
		if pressed:
			if event.position.distance_to(start) > 6: dragged = true
			if dragged: pan(event.position - event.relative, event.position)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			yaw -= event.relative.x * 0.006
	elif event is InputEventMagnifyGesture:
		desired_zoom = clampf(desired_zoom / event.factor, 28, 135)
	elif event is InputEventPanGesture:
		pan(event.position, event.position + event.delta * 12)
	elif event is InputEventScreenTouch:
		if event.canceled:
			touches.erase(event.index)
			touch_consumed = true
			return
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				start = event.position
				touch_consumed = false
			else: touch_consumed = true
		else:
			if touches.has(event.index) and touches.size() == 1 and not touch_consumed:
				var point: Variant = ground_at(event.position)
				if point != null: parcel_tapped.emit(event.position)
			touches.erase(event.index)
	elif event is InputEventScreenDrag and touches.has(event.index):
		if event.position.distance_to(start) > 7: touch_consumed = true
		if touches.size() == 1:
			pan(touches[event.index], event.position)
		else:
			var keys := touches.keys()
			var other: int = keys[1] if keys[0] == event.index else keys[0]
			var old: Vector2 = touches[event.index] - touches[other]
			var fresh: Vector2 = event.position - touches[other]
			if fresh.length() > 10 and old.length() > 10:
				desired_zoom = clampf(desired_zoom * old.length() / fresh.length(), 28, 135)
				yaw -= old.angle_to(fresh)
			pan((touches[event.index] + touches[other]) / 2, (event.position + touches[other]) / 2)
		touches[event.index] = event.position
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q: rotate_view(-1)
		if event.keycode == KEY_E: rotate_view(1)
		if event.keycode == KEY_HOME: focus(Vector3(-8, 0, 2), false)
