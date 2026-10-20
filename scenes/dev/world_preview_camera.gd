class_name WorldPreviewCamera
extends Camera3D
## T-001 önizleme kamerası (DEV; T-003'ün gerçek kamera rig'i DEĞİL). Odak noktası + yön + eğim + uzaklık.
## Fare: sol sürükle = kaydır, sağ/orta sürükle = döndür/eğ, tekerlek = yakınlaş. Klavye: WASD kaydır (Shift hızlı),
## Q/E döndür, R/F eğim, Z/X yakınlaş, 1-4 = preset. Mac izleme yüzeyi: iki parmak kaydır = kaydır, sıkıştır = yakınlaş.
## Simülasyon durumuna dokunmaz; WorldData'yı yalnız ön ayar hesabı için okur.

const PRESETS: Array[StringName] = [&"metro", &"bay_west", &"plain_east", &"harbor"]
const MIN_DISTANCE := 150.0
const MAX_DISTANCE := 90000.0
const MIN_PITCH := 8.0
const MAX_PITCH := 88.0

var focus: Vector3 = Vector3.ZERO
var heading_deg: float = 0.0
var pitch_deg: float = 50.0
var distance: float = 40000.0
## (x, z) → zemin yüksekliği; kamera zeminin altına inmesin ve odak zemini izlesin.
var ground_height: Callable = Callable()
var current_preset: StringName = &"metro"

var _world: WorldData
var _drag_pan: bool = false
var _drag_orbit: bool = false


## Preset kamera durumu. Odaklar WorldData'dan türer (veri değişirse önizleme izler).
func apply_preset(preset: StringName, world: WorldData) -> void:
	_world = world
	current_preset = preset
	var size := world.size
	var center := world.origin + size * 0.5
	var f := center
	fov = 40.0
	match preset:
		&"bay_west":
			f = world.origin + size * Vector2(0.17, 0.5)
			heading_deg = 78.0
			pitch_deg = 32.0
			distance = 17000.0
		&"plain_east":
			var d4 := world.region_by_code(&"D4")
			var d5 := world.region_by_code(&"D5")
			f = ((d4.anchor + d5.anchor) * 0.5 + Vector2(0.0, 1500.0)) if d4 != null and d5 != null else center
			heading_deg = 150.0
			pitch_deg = 38.0
			distance = 24000.0
		&"harbor":
			f = world.port_site.position if world.port_site != null else center
			heading_deg = 235.0
			pitch_deg = 42.0
			distance = 8500.0
		_:
			current_preset = &"metro"
			f = center + Vector2(0.0, size.y * 0.06)
			heading_deg = 0.0
			pitch_deg = 50.0
			distance = size.x * 1.45
	focus = Vector3(f.x, 0.0, f.y)
	_update_transform()


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	var speed := distance * 0.55 * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	if move != Vector2.ZERO:
		_pan_ground(move.normalized() * speed * delta)
	if Input.is_physical_key_pressed(KEY_Q):
		heading_deg -= 60.0 * delta
	if Input.is_physical_key_pressed(KEY_E):
		heading_deg += 60.0 * delta
	if Input.is_physical_key_pressed(KEY_R):
		pitch_deg = minf(pitch_deg + 40.0 * delta, MAX_PITCH)
	if Input.is_physical_key_pressed(KEY_F):
		pitch_deg = maxf(pitch_deg - 40.0 * delta, MIN_PITCH)
	if Input.is_physical_key_pressed(KEY_Z):
		_zoom(pow(0.4, delta))
	if Input.is_physical_key_pressed(KEY_X):
		_zoom(pow(2.5, delta))
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				_drag_pan = button.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_drag_orbit = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 0.88)
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _drag_orbit:
			heading_deg += motion.relative.x * 0.3
			pitch_deg = clampf(pitch_deg + motion.relative.y * 0.3, MIN_PITCH, MAX_PITCH)
		elif _drag_pan:
			_pan_ground(Vector2(-motion.relative.x, motion.relative.y) * distance * 0.0011)
		return
	var pan_gesture := event as InputEventPanGesture
	if pan_gesture != null:
		_pan_ground(Vector2(pan_gesture.delta.x, -pan_gesture.delta.y) * distance * 0.0016)
		return
	var magnify := event as InputEventMagnifyGesture
	if magnify != null:
		_zoom(1.0 / maxf(magnify.factor, 0.05))
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var digit := key.physical_keycode - KEY_1
		if digit >= 0 and digit < PRESETS.size() and _world != null:
			apply_preset(PRESETS[digit], _world)


## Zemin düzleminde, kameranın yönüne göre kaydırma (x = sağ, y = ileri), metre.
func _pan_ground(offset: Vector2) -> void:
	var h := deg_to_rad(heading_deg)
	var forward := Vector3(sin(h), 0.0, -cos(h))
	var right := Vector3(cos(h), 0.0, sin(h))
	focus += right * offset.x + forward * offset.y
	if _world != null:
		focus.x = clampf(focus.x, _world.origin.x, _world.origin.x + _world.size.x)
		focus.z = clampf(focus.z, _world.origin.y, _world.origin.y + _world.size.y)


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)


func _update_transform() -> void:
	if ground_height.is_valid():
		focus.y = float(ground_height.call(focus.x, focus.z))
	var h := deg_to_rad(heading_deg)
	var p := deg_to_rad(pitch_deg)
	var forward := Vector3(sin(h) * cos(p), -sin(p), -cos(h) * cos(p))
	var pos := focus - forward * distance
	if ground_height.is_valid():
		var floor_y := float(ground_height.call(pos.x, pos.z)) + 30.0
		pos.y = maxf(pos.y, floor_y)
	near = clampf(distance * 0.02, 1.0, 700.0)
	far = distance * 3.0 + 60000.0
	global_position = pos
	look_at(focus, Vector3.UP)
