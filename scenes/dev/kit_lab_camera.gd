class_name KitLabCamera
extends Camera3D
## kit_lab kamerası (DEV). Odak + yön + eğim + uzaklık; spec 9.1 preset'leri. Fare: sol sürükle = döndür/eğ,
## sağ/orta = kaydır, tekerlek = yakınlaş. WASD kaydır, Q/E döndür, R/F eğim, Z/X yakınlaş.

const MIN_DISTANCE := 20.0
const MAX_DISTANCE := 6000.0

var focus: Vector3 = Vector3.ZERO
var heading_deg: float = 0.0   ## 0 = -Z'ye bakar (ön cepheleri +Z olan binalar kameraya döner)
var pitch_deg: float = 40.0
var distance: float = 400.0
var current_preset: StringName = &"kit_block"

var _orbit: bool = false
var _pan: bool = false


func apply_state(f: Vector3, heading: float, pitch: float, dist: float, field_of_view: float) -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	focus = f
	heading_deg = heading
	pitch_deg = pitch
	distance = dist
	fov = field_of_view
	near = maxf(0.5, dist * 0.01)
	far = maxf(4000.0, dist * 6.0)
	_update()


func apply_ortho(center: Vector3, size_m: float, back_m: float) -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = size_m
	near = 1.0
	far = absf(back_m) * 3.0
	global_position = center + Vector3(0.0, 0.0, back_m)
	look_at(center, Vector3.UP)


func _update() -> void:
	pitch_deg = clampf(pitch_deg, 5.0, 90.0)
	distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	var h := deg_to_rad(heading_deg)
	var p := deg_to_rad(pitch_deg)
	var forward := Vector3(sin(h), 0.0, -cos(h))
	var offset := (-forward * cos(p) + Vector3.UP * sin(p)) * distance
	var up := Vector3.UP if pitch_deg < 89.0 else forward
	look_at_from_position(focus + offset, focus, up)


func _unhandled_input(event: InputEvent) -> void:
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbit = mb.pressed
		elif mb.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_pan = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance *= 0.9
			_update()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance /= 0.9
			_update()
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _orbit:
			heading_deg -= mm.relative.x * 0.3
			pitch_deg += mm.relative.y * 0.3
			_update()
		elif _pan:
			var h := deg_to_rad(heading_deg)
			var right := Vector3(cos(h), 0.0, sin(h))
			var fwd := Vector3(sin(h), 0.0, -cos(h))
			focus += (-right * mm.relative.x + fwd * mm.relative.y) * distance * 0.002
			_update()


func _process(delta: float) -> void:
	if projection == Camera3D.PROJECTION_ORTHOGONAL:
		return
	var move := Vector2.ZERO
	var changed := false
	if Input.is_key_pressed(KEY_W):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S):
		move.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if move != Vector2.ZERO:
		var h := deg_to_rad(heading_deg)
		var fwd := Vector3(sin(h), 0.0, -cos(h))
		var right := Vector3(cos(h), 0.0, sin(h))
		focus += (fwd * move.y + right * move.x) * distance * 0.8 * delta
		changed = true
	if Input.is_key_pressed(KEY_Q):
		heading_deg -= 60.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_E):
		heading_deg += 60.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_R):
		pitch_deg += 40.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_F):
		pitch_deg -= 40.0 * delta
		changed = true
	if Input.is_key_pressed(KEY_Z):
		distance *= 1.0 - 0.8 * delta
		changed = true
	if Input.is_key_pressed(KEY_X):
		distance *= 1.0 + 0.8 * delta
		changed = true
	if changed:
		_update()
