class_name CameraRig
extends Node3D
## Çok ölçekli kamera rig'i (T-003; WLD-01, TEK-03, TEK-04, PLT-02, VIS-03): metro (~50 km) -> ilçe -> sokak (~25 m)
## TEK dünyada KESİNTİSİZ gezinti. Yörünge/odak modeli: odak = zemine oturan dünya noktası + uzaklık + yön + eğim.
##
## GİRDİ YALNIZ `InputProfile` SİNYALLERİYLE (ADR-0004; masaüstü ve dokunmatik AYNI fiiller): pan_requested,
## zoom_requested, rotate_requested + held_*_axis. Ham olaydan yalnız işaretçinin EKRAN KONUMU okunur (pan sinyalinde
## konum yok; içerik imleci/parmağı izlesin diye) -- fiil kararı hiçbir yerde ham olaydan verilmez. Bu sözleşme
## eksikliği raporlandı (pan_requested'e anchor). Eğim (pitch) fiili sözleşmede YOK: R/F tuşları GEÇİCİ.
## Girdi `_unhandled_input`'tadır: UI (Control) olayı önce tüketir (ADR-0004).
##
## Kamera bir görünüm kavramıdır: WorldData'yı yalnız OKUR, simülasyona dokunmaz.
##
## ORIGIN REBASING (ADR-0002 §2): `view_root` (arazi, işaretler vb. dünya içeriği) `-rebase_origin` kadar kaydırılır;
## kamera origin'e GÖRE konumlanır. Origin 512 m ızgarasına oturur (32-bit'te tam) ve odak 1536 m uzaklaşınca yeniden
## oturur. Kayma aynı karede hem içeriğe hem kameraya uygulanır: ekranda sıçrama yok (test: aynı dünya noktası
## öncesi/sonrası aynı piksel). `view_root` verilmezse rebasing kapalıdır (origin sıfır).
##
## Yumuşatma: hedef durum anında güncellenir, görünen durum üstel olarak yaklaşır (kare hızından bağımsız). Odak ve
## uzaklık doğrusal ilerler -> tek zoom adımında imleç altındaki nokta yumuşatma boyunca da yerinde kalır.
## Sürekli zoom varsayılan (UX Q-011 AÇIK): `continuous_zoom = false` ölçek kapılarına adım adım zoom yapar (ayar).

signal rebased(new_origin: Vector2)
signal preset_applied(preset_name: StringName)

## Kapılı zoom (`continuous_zoom = false`) basamakları, metre (YER TUTUCU; ayar, tasarım kararı değil).
const ZOOM_GATES_M: Array[float] = [30.0, 150.0, 800.0, 4000.0, 20000.0, 58000.0]
const SMOOTH_RATE_PER_S := 14.0
const HELD_PAN_SPEED_PER_DISTANCE := 0.55
const HELD_ROTATE_DEG_PER_S := 60.0
const HELD_ZOOM_BASE_PER_S := 2.5
## GEÇİCİ eğim tuşları (sözleşmede eğim fiili yok): R yukarı bak (dik), F alçalt.
const TILT_DEG_PER_S := 40.0
const SNAP_EPS_M := 0.001

@export var smoothing_enabled: bool = true
@export var smoothing_rate: float = SMOOTH_RATE_PER_S
## true (varsayılan): ölçek kapısı yok, zoom sürekli akar. false: her zoom olayı bir sonraki kapıya adım atar.
@export var continuous_zoom: bool = true

var camera: Camera3D
## (x, z) -> zemin yüksekliği (m); görünümde `TerrainView.surface_height_at`. Boşsa düz sıfır zemin.
var ground_height: Callable = Callable()
## Rebasing uygulanacak dünya içeriği kökü (boşsa rebasing kapalı).
var view_root: Node3D = null
var input_profile: InputProfile = null
var world: WorldData = null
var preset_name: StringName = &"metro"
var rebase_origin: Vector2 = Vector2.ZERO
var rebase_count: int = 0
## Testler/başsız çalıştırma için sabit görünüm boyutu (0 = gerçek viewport).
var viewport_size_override: Vector2 = Vector2.ZERO

var _target: CameraState = CameraState.new()
var _current: CameraState = CameraState.new()
var _pointer_px: Vector2 = Vector2(NAN, NAN)
var _tilt_up: bool = false
var _tilt_down: bool = false
var _ready_done: bool = false


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(camera)
	if input_profile == null:
		input_profile = PlatformProfile.current().create_input_profile()
	_connect_input_profile()
	_ready_done = true
	_apply_pose()


func _process(delta: float) -> void:
	if input_profile != null:
		input_profile.process(delta)
		_apply_held(delta)
	_smooth(delta)
	_apply_pose()


func _unhandled_input(event: InputEvent) -> void:
	if _scroll_blocked_by_ui(event):
		return
	_note_pointer(event)
	_note_tilt_key(event)
	if input_profile != null and input_profile.handle_event(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_input()


# --- Genel API ---

func make_current() -> void:
	camera.make_current()


## Dünya + zemin yüksekliği işlevi (görünüm: `TerrainView.surface_height_at`). Dünya sınırı pan'ı kırpar.
func set_world(new_world: WorldData, ground: Callable) -> void:
	world = new_world
	ground_height = ground


## Preset metni (bkz `CameraPresets`). Geçersizse net hata + metro yedek; dönüş: preset geçerli miydi.
func apply_preset(spec: String) -> bool:
	if world == null:
		push_error("CameraRig.apply_preset: önce set_world()")
		return false
	var r := CameraPresets.resolve(spec, world, ground_height)
	if not r["ok"]:
		push_error("CameraRig: %s; metro kullanılıyor" % r["error"])
	preset_name = r["name"]
	apply_state(r["state"], true)
	preset_applied.emit(preset_name)
	return r["ok"]


## Durumu hedef yapar; `snap` ise yumuşatmadan anında. Değerler sınırlara kenetlenir.
func apply_state(state: CameraState, snap: bool = true) -> void:
	if not state.is_valid():
		push_error("CameraRig.apply_state: geçersiz durum (NaN/sıfır uzaklık) yok sayıldı")
		return
	_target = _sanitized(state)
	if snap:
		_current = _target.copy()
	_apply_pose()


## Yumuşatmayı bitirip hedefe oturur (capture/test).
func snap_to_target() -> void:
	_current = _target.copy()
	_apply_pose()


func target_state() -> CameraState:
	return _target.copy()


func current_state() -> CameraState:
	return _current.copy()


## Görünen kamera uzaklığı (m): gölge/LOD kararları için.
func distance() -> float:
	return _current.distance


func focus_xz() -> Vector2:
	return Vector2(_current.focus_x, _current.focus_z)


func world_bounds() -> Rect2:
	return world.bounds() if world != null else Rect2()


## Dünya noktası -> ekran pikseli (gerçek Camera3D boru hattı: rebasing sonrası da aynı).
func world_to_screen(wx: float, wy: float, wz: float) -> Vector2:
	var local := Vector3(wx - rebase_origin.x, wy, wz - rebase_origin.y)
	if camera.is_position_behind(local):
		return Vector2(NAN, NAN)
	return camera.unproject_position(local)


## Ekran pikselinin altındaki zemin {ok, x, y, z} (görünen kameradan).
func screen_to_ground(px: Vector2) -> Dictionary:
	return CameraMath.grab_point(_current, px, _viewport_size(), _ground())


## Origin'i elle taşır (test/araç). İçerik ve kamera aynı anda kayar.
func set_rebase_origin(origin: Vector2) -> void:
	rebase_origin = origin
	if view_root != null:
		view_root.position = Vector3(-origin.x, 0.0, -origin.y)
	rebase_count += 1
	rebased.emit(origin)
	_place_camera()


func reset_input() -> void:
	if input_profile != null:
		input_profile.reset()
	_tilt_up = false
	_tilt_down = false


# --- Girdi fiilleri (InputProfile sinyalleri) ---

func on_pan(screen_delta: Vector2) -> void:
	var size := _viewport_size()
	var to_px := _pointer_px if _pointer_px.is_finite() else size * 0.5 + screen_delta
	_target = CameraMath.pan_grab(_target, to_px - screen_delta, to_px, size, _ground(), world_bounds())
	_settle_if_unsmoothed()


func on_zoom(factor: float, anchor: Vector2) -> void:
	var f := factor if continuous_zoom else _gated_factor(factor)
	_target = CameraMath.zoom_at(_target, f, anchor, _viewport_size(), _ground(), world_bounds())
	_settle_if_unsmoothed()


func on_rotate(radians: float, anchor: Vector2) -> void:
	_target = CameraMath.rotate_about(_target, radians, anchor, _viewport_size(), _ground(), world_bounds())
	_settle_if_unsmoothed()


## GEÇİCİ: eğim (derece, + = daha dik).
func tilt(delta_deg: float) -> void:
	if is_finite(delta_deg):
		_target.pitch_deg = CameraMath.clamp_pitch_deg(_target.pitch_deg + delta_deg)
		_settle_if_unsmoothed()


# --- Özel ---

func _connect_input_profile() -> void:
	input_profile.pan_requested.connect(on_pan)
	input_profile.zoom_requested.connect(on_zoom)
	input_profile.rotate_requested.connect(on_rotate)


func _apply_held(delta: float) -> void:
	var center := _viewport_size() * 0.5
	var pan := input_profile.held_pan_axis()
	if pan != Vector2.ZERO:
		var step := _target.distance * HELD_PAN_SPEED_PER_DISTANCE * delta
		_target = CameraMath.move_focus(_target, pan.x * step, -pan.y * step, _ground(), world_bounds())
	var rot := input_profile.held_rotate_axis()
	if rot != 0.0:
		on_rotate(rot * deg_to_rad(HELD_ROTATE_DEG_PER_S) * delta, center)
	var zoom := input_profile.held_zoom_axis()
	if zoom != 0.0:
		on_zoom(pow(HELD_ZOOM_BASE_PER_S, zoom * delta), center)
	var tilt_axis := float(_tilt_up) - float(_tilt_down)
	if tilt_axis != 0.0:
		tilt(tilt_axis * TILT_DEG_PER_S * delta)


## Yumuşatma kapalıyken görünen durum hedefle birlikte hareket eder (olay anında; kare beklemez).
func _settle_if_unsmoothed() -> void:
	if not smoothing_enabled:
		_current = _target.copy()
		_apply_pose()


func _smooth(delta: float) -> void:
	if not smoothing_enabled:
		_current = _target.copy()
		return
	_current.approach(_target, 1.0 - exp(-smoothing_rate * maxf(delta, 0.0)))
	if _current.is_close_to(_target, SNAP_EPS_M, 0.001):
		_current = _target.copy()


func _apply_pose() -> void:
	if not _ready_done:
		return
	if view_root != null:
		var dx := absf(_current.focus_x - rebase_origin.x)
		var dz := absf(_current.focus_z - rebase_origin.y)
		if rebase_count == 0 or maxf(dx, dz) > CameraMath.REBASE_TRIGGER_M:
			set_rebase_origin(Vector2(CameraMath.snap_origin(_current.focus_x), CameraMath.snap_origin(_current.focus_z)))
			return
	_place_camera()


func _place_camera() -> void:
	if camera == null:
		return
	var s := _current
	var eye := CameraMath.eye_relative(s, rebase_origin.x, rebase_origin.y, _ground())
	camera.transform = Transform3D(CameraMath.basis_for(s.heading_deg, s.pitch_deg), eye)
	var nf := CameraMath.near_far(s.distance)
	camera.near = nf.x
	camera.far = nf.y
	camera.fov = s.fov_deg


func _sanitized(state: CameraState) -> CameraState:
	var s := state.copy()
	s.distance = CameraMath.clamp_distance(s.distance)
	s.pitch_deg = CameraMath.clamp_pitch_deg(s.pitch_deg)
	s.heading_deg = wrapf(s.heading_deg, 0.0, 360.0)
	var b := world_bounds()
	if b.has_area():
		s.focus_x = clampf(s.focus_x, b.position.x, b.end.x)
		s.focus_z = clampf(s.focus_z, b.position.y, b.end.y)
	return CameraMath.reseat(s, _ground())


## Zemin işlevi; verilmemişse düz sıfır zemin (başsız/boş sahne).
func _ground() -> Callable:
	return ground_height if ground_height.is_valid() else Callable(CameraRig, "_flat_ground")


static func _flat_ground(_x: float, _z: float) -> float:
	return 0.0


func _viewport_size() -> Vector2:
	if viewport_size_override.x > 0.0 and viewport_size_override.y > 0.0:
		return viewport_size_override
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1600.0, 900.0)
	return size if size.x > 0.0 and size.y > 0.0 else Vector2(1600.0, 900.0)


## Kapılı zoom: yönüne göre bir sonraki kapıya çarpan.
func _gated_factor(factor: float) -> float:
	if not is_finite(factor) or factor <= 0.0 or is_equal_approx(factor, 1.0):
		return 1.0
	var d := _target.distance
	var goal := d
	if factor > 1.0:
		for i in range(ZOOM_GATES_M.size() - 1, -1, -1):
			if ZOOM_GATES_M[i] < d * 0.98:
				goal = ZOOM_GATES_M[i]
				break
		if goal == d:
			goal = ZOOM_GATES_M[0]
	else:
		for gate in ZOOM_GATES_M:
			if gate > d * 1.02:
				goal = gate
				break
		if goal == d:
			goal = ZOOM_GATES_M[ZOOM_GATES_M.size() - 1]
	return d / goal


## UI dünyadan önce (ADR-0004). Godot, STOP filtreli bir Control'ün üstündeki tıklama/sürüklemeyi tüketir ama
## TEKERLEK ve trackpad jestleri `_unhandled_input`'a sızar (T-003 duman testinde ölçüldü); imleç STOP bir Control
## üstündeyse bu olayları dünyaya iletmeyiz.
func _scroll_blocked_by_ui(event: InputEvent) -> bool:
	var wheel := event as InputEventMouseButton
	var is_scroll := (wheel != null and wheel.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
			MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]) or event is InputEventGesture
	if not is_scroll or not is_inside_tree():
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP


## Yalnız işaretçinin EKRAN KONUMU: pan'da içerik imleci/parmağı izlesin (fiil kararı değil).
func _note_pointer(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse != null:
		_pointer_px = mouse.position
		return
	var gesture := event as InputEventGesture
	if gesture != null:
		_pointer_px = gesture.position
		return
	var touch := event as InputEventScreenTouch
	if touch != null:
		_pointer_px = touch.position
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		_pointer_px = drag.position


## GEÇİCİ eğim tuşları (R/F). UI olayı tüketirse buraya gelmez.
func _note_tilt_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return
	var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_R:
		_tilt_up = key.pressed
	elif code == KEY_F:
		_tilt_down = key.pressed
