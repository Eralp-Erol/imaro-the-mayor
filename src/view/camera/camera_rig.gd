# gdlint:disable=max-public-methods
class_name CameraRig
extends Node3D
## Çok ölçekli kamera rig'i (T-003; WLD-01, TEK-03, TEK-04, PLT-02, VIS-03): uzak uçtan (`CameraEnvelope.d_max_m`,
## ~18 km) sokağa (`d_min_m`, ~50 m) TEK dünyada KESİNTİSİZ gezinti. Yörünge/odak modeli: odak = zemine oturan dünya
## noktası + uzaklık + yön + eğim. Sınırlar ve K1 kadraj kuralı `CameraEnvelope`'tan (veri:
## `data/view/camera_envelope.json`, T-064): hem hedef hem yumuşatılmış ara poz zarftan geçer (iki geçerli durumun
## aradeğeri geçerli olmayabilir). Pan uzaklığı değiştirmez (pan çözüm sırası: eğim -> odak).
##
## GİRDİ YALNIZ `InputProfile` SİNYALLERİYLE (ADR-0004; masaüstü ve dokunmatik AYNI fiiller): pan_requested,
## zoom_requested, rotate_requested, camera_tilt_requested + held_*_axis. Ham olaydan yalnız işaretçinin EKRAN KONUMU
## okunur (pan sinyalinde konum yok; içerik imleci/parmağı izlesin diye) -- fiil kararı hiçbir yerde ham olaydan
## verilmez. Bu sözleşme eksikliği raporlandı (pan_requested'e anchor).
##
## EĞİM: İSTENEN eğim (`desired_pitch_deg`, oyuncunun tercihi) ile FİİLİ eğim (`target_state().pitch_deg`) ayrıdır.
## K1/zarf yalnız fiili eğimi `max(istenen, gereken)` olarak yükseltir; istenen eğime dokunmaz. Zoom-in gereken eğimi
## düşürünce fiili eğim (mevcut yumuşatmayla) tercihe geri iner. Tercihi yalnız oyuncunun eğim fiili, preset/Home
## (başlangıç eğimi) ve `apply_state` ile açıkça verilen eğim değiştirir; zoom/pan/döndür değiştirmez.
## Girdi `_unhandled_input`'tadır: UI (Control) olayı önce tüketir (ADR-0004).
##
## BİNA FARKINDA GÖZ AÇIKLIĞI (ADR-0007 Ek c): yatay bakışta (3° taban) göz yerden ~3 m kalır ve yapıların içine
## girebilir. `roof_clearance` (RoofClearance; yapı sütunlarından deterministik çatı yükseklikleri) verilirse göz,
## çevresindeki `envelope.roof_radius_m` içindeki en yüksek çatı + `roof_margin_m` üstüne YUMUŞAKÇA itilir. Yalnız
## gözün y'si değişir (dönüş, eğim, odak, uzaklık aynı: istenen ve fiili eğim, K1 ve eğim tabanı etkilenmez); yalnız
## yakın bantlarda (`roof_active_below_m`, sonra `roof_fade_to_m`e sönüm). Verilmezse rig, sahnedeki
## `BuildingView.ROOF_SOURCE_GROUP` grubundan kaynağı kendisi bulur. Seçim/pan/zoom matematiği HAM yörünge gözünü
## kullanır (`eye_lift_m` yalnız sunum ofsetidir; arazi açıklığı da böyledir).
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
## Ölçek bandı (street/neighborhood/district/metro) ±%10 histerezisle değişti. HUD metni yalnız bundan (`zoom.<band>`).
signal scale_band_changed(band: StringName)

const SMOOTH_RATE_PER_S := 14.0
const HELD_PAN_SPEED_PER_DISTANCE := 0.55
const HELD_ROTATE_DEG_PER_S := 60.0
const HELD_ZOOM_BASE_PER_S := 2.5
## Tuşla eğim hızı (R dikleş, F alçal; `InputProfile.held_tilt_axis`).
const TILT_DEG_PER_S := 40.0
const SNAP_EPS_M := 0.001
const ROOF_PROBE_INTERVAL_S := 0.5

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
var preset_name: StringName = CameraPresets.FALLBACK
## Kamera zarfı (oyuncu zarfı; `--envelope=legacy` yalnız geliştirici sahnesi/araçları verir). Kapılı zoom da buradan.
var envelope: CameraEnvelope = null
## Çatı yükseklik sağlayıcısı (boşsa bina farkında açıklık kapalı; sahnede grup üzerinden aranır, bkz
## `_probe_roof_source`).
var roof_clearance: RoofClearance = null
## Ölçek bandı (son sinyal).
var scale_band: StringName = &""
## Home hedefi: başlangıç ilçe kodu (oturum/veri; boşsa `core`). Kodda ilçe kimliği yoktur.
var home_district: StringName = &""
var rebase_origin: Vector2 = Vector2.ZERO
var rebase_count: int = 0
## Testler/başsız çalıştırma için sabit görünüm boyutu (0 = gerçek viewport).
var viewport_size_override: Vector2 = Vector2.ZERO

var _target: CameraState = CameraState.new()
var _current: CameraState = CameraState.new()
var _pointer_px: Vector2 = Vector2(NAN, NAN)
## Oyuncunun istediği eğim (derece). Fiili eğim zarf/K1 yüzünden bundan dik olabilir (alçak olamaz, zarf tabanı hariç).
var _desired_pitch: float = 50.0
var _ready_done: bool = false
## Gözün çatı açıklığı için yukarı itildiği miktar (m, >= 0): sunum ofseti, kare başı yumuşar.
var _eye_lift: float = 0.0
var _roof_probe_s: float = 0.0


func _init() -> void:
	envelope = CameraEnvelope.load_default()


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
	_advance_eye_lift(delta)
	_apply_pose()


func _unhandled_input(event: InputEvent) -> void:
	if _scroll_blocked_by_ui(event):
		return
	_note_pointer(event)
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


## Preset metni (bkz `CameraPresets`). Geçersizse net hata + `core` yedek; dönüş: preset geçerli miydi.
func apply_preset(spec: String) -> bool:
	if world == null:
		push_error("CameraRig.apply_preset: önce set_world()")
		return false
	return _apply_resolved(CameraPresets.resolve(spec, world, _ground(), envelope, _aspect()))


## Home / açılış (`start_view`): `home_district` yoksa `core`.
func go_home() -> bool:
	if world == null:
		push_error("CameraRig.go_home: önce set_world()")
		return false
	return _apply_resolved(CameraPresets.start_view(world, home_district, _ground(), envelope, _aspect()))


## Durumu hedef yapar; `snap` ise yumuşatmadan anında. Değerler zarfa (sınırlar + K1) çözülür.
func apply_state(state: CameraState, snap: bool = true) -> void:
	if not state.is_valid():
		push_error("CameraRig.apply_state: geçersiz durum (NaN/sıfır uzaklık) yok sayıldı")
		return
	# Eğim, çağıranın verdiği değerse yeni tercihtir; fiili eğimle aynı bırakıldıysa (odak taşıyan çağıranlar)
	# mevcut tercih korunur.
	if not is_equal_approx(state.pitch_deg, _target.pitch_deg):
		_desired_pitch = clampf(state.pitch_deg, 0.0, envelope.pitch_max_deg)
	_target = _sanitized(state)
	if snap:
		_current = _target.copy()
		_eye_lift = _eye_lift_goal()
	_apply_pose()


## Yumuşatmayı bitirip hedefe oturur (capture/test).
func snap_to_target() -> void:
	_current = _target.copy()
	_eye_lift = _eye_lift_goal()
	_apply_pose()


## Oyuncunun istediği eğim (derece); fiili eğim (`target_state().pitch_deg`) bundan dik olabilir (K1/zarf).
func desired_pitch_deg() -> float:
	return _desired_pitch


## Gözün çatı açıklığı için yukarı itildiği miktar (m, >= 0).
func eye_lift_m() -> float:
	return _eye_lift


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


# --- Girdi fiilleri (InputProfile sinyalleri) ---

func on_pan(screen_delta: Vector2) -> void:
	var size := _viewport_size()
	var to_px := _pointer_px if _pointer_px.is_finite() else size * 0.5 + screen_delta
	_target = _enforce_desired(CameraMath.pan_grab(_target, to_px - screen_delta, to_px, size, _ground(),
			world_bounds()), CameraEnvelope.MODE_PAN)
	_settle_if_unsmoothed()


func on_zoom(factor: float, anchor: Vector2) -> void:
	var f := factor if continuous_zoom else _gated_factor(factor)
	var limits := Vector2(envelope.d_min_m, envelope.d_max_m)
	_target = _enforce_desired(CameraMath.zoom_at(_target, f, anchor, _viewport_size(), _ground(), world_bounds(),
			limits))
	_settle_if_unsmoothed()


func on_rotate(radians: float, anchor: Vector2) -> void:
	_target = _enforce_desired(CameraMath.rotate_about(_target, radians, anchor, _viewport_size(), _ground(),
			world_bounds()))
	_settle_if_unsmoothed()


## Oyuncu eğimi (derece, + = daha dik): TERCİHİ günceller. Tercih aralığı [zarfın en alçak eğimi, pitch_max]; FİİLİ
## eğim ayrıca pitch_min(d) ve K1 ile sınırlanır. Dikleştirme GÖRÜNEN eğimden başlar (anında karşılık); alçaltma
## tercihten düşer (K1/zarf tabanında görünür değişmez ama zoom-in'de alçak eğim beklenir).
func tilt(delta_deg: float) -> void:
	if not is_finite(delta_deg) or delta_deg == 0.0:
		return
	var base := maxf(_desired_pitch, _target.pitch_deg) if delta_deg > 0.0 else minf(_desired_pitch, _target.pitch_deg)
	_desired_pitch = clampf(base + delta_deg, envelope.pitch_min_deg(envelope.d_min_m), envelope.pitch_max_deg)
	_target = _enforce_desired(_target)
	_settle_if_unsmoothed()


# --- Özel ---

func _connect_input_profile() -> void:
	input_profile.pan_requested.connect(on_pan)
	input_profile.zoom_requested.connect(on_zoom)
	input_profile.rotate_requested.connect(on_rotate)
	input_profile.camera_home_requested.connect(go_home)
	input_profile.camera_tilt_requested.connect(tilt)


func _apply_held(delta: float) -> void:
	var center := _viewport_size() * 0.5
	var pan := input_profile.held_pan_axis()
	if pan != Vector2.ZERO:
		var step := _target.distance * HELD_PAN_SPEED_PER_DISTANCE * delta
		_target = _enforce_desired(CameraMath.move_focus(_target, pan.x * step, -pan.y * step, _ground(),
				world_bounds()), CameraEnvelope.MODE_PAN)
	var rot := input_profile.held_rotate_axis()
	if rot != 0.0:
		on_rotate(rot * deg_to_rad(HELD_ROTATE_DEG_PER_S) * delta, center)
	var zoom := input_profile.held_zoom_axis()
	if zoom != 0.0:
		on_zoom(pow(HELD_ZOOM_BASE_PER_S, zoom * delta), center)
	var tilt_axis := input_profile.held_tilt_axis()
	if tilt_axis != 0.0:
		tilt(tilt_axis * TILT_DEG_PER_S * delta)


## Yumuşatma kapalıyken görünen durum hedefle birlikte hareket eder (olay anında; kare beklemez).
func _settle_if_unsmoothed() -> void:
	if not smoothing_enabled:
		_current = _target.copy()
		_eye_lift = _eye_lift_goal()
		_apply_pose()


func _smooth(delta: float) -> void:
	if not smoothing_enabled:
		_current = _target.copy()
		return
	_current.approach(_target, 1.0 - exp(-smoothing_rate * maxf(delta, 0.0)))
	if _current.is_close_to(_target, SNAP_EPS_M, 0.001):
		_current = _target.copy()
	else:
		# İki geçerli durumun aradeğeri geçerli olmayabilir: yumuşatılmış poz da zarftan geçer (K1).
		_current = _enforce(_current)


## Çatı açıklığı hedefi (m): çevredeki en yüksek çatı + pay, görünen gözün (arazi açıklıklı) üstünde kalan kısım;
## uzaklık ağırlığı ile çarpılır. Sağlayıcı yoksa ya da çatı yoksa 0. Yalnız `_current` okunur; kaldırma gözün x/z'sini
## değiştirmediği için hedef kendine geri beslenmez.
func _eye_lift_goal() -> float:
	if roof_clearance == null or envelope == null:
		return 0.0
	var weight := envelope.roof_weight(_current.distance)
	if weight <= 0.0:
		return 0.0
	var eye := CameraMath.eye_xyz(_current, _ground())
	var roof := roof_clearance.max_roof_y(eye[0], eye[2], envelope.roof_radius_m)
	if roof <= RoofClearance.NO_ROOF:
		return 0.0
	return maxf(roof + envelope.roof_margin_m - eye[1], 0.0) * weight


## Kaldırmayı hedefe üstel yaklaştırır (kare hızından bağımsız; yükselme ve alçalma aynı hız). Yumuşatma kapalıysa
## anında.
func _advance_eye_lift(delta: float) -> void:
	if roof_clearance == null:
		_probe_roof_source(delta)
		if roof_clearance == null:
			return
	var goal := _eye_lift_goal()
	if not smoothing_enabled or envelope.roof_smooth_rate_per_s <= 0.0:
		_eye_lift = goal
		return
	_eye_lift = lerpf(_eye_lift, goal, 1.0 - exp(-envelope.roof_smooth_rate_per_s * maxf(delta, 0.0)))
	if absf(_eye_lift - goal) < SNAP_EPS_M:
		_eye_lift = goal


## Sağlayıcı enjekte edilmediyse sahnedeki BuildingView'u (grup) yarım saniyede bir arar.
func _probe_roof_source(delta: float) -> void:
	if not is_inside_tree():
		return
	_roof_probe_s -= delta
	if _roof_probe_s > 0.0:
		return
	_roof_probe_s = ROOF_PROBE_INTERVAL_S
	for node in get_tree().get_nodes_in_group(BuildingView.ROOF_SOURCE_GROUP):
		var source := node as BuildingView
		if source != null:
			roof_clearance = source.roof_clearance()
			return


func _apply_pose() -> void:
	if not _ready_done:
		return
	_update_band()
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
	eye.y += _eye_lift
	camera.transform = Transform3D(CameraMath.basis_for(s.heading_deg, s.pitch_deg), eye)
	var nf := CameraMath.near_far(s.distance)
	camera.near = nf.x
	camera.far = nf.y
	camera.fov = s.fov_deg


func _apply_resolved(r: Dictionary) -> bool:
	if not r["ok"]:
		push_error("CameraRig: %s; %s kullanılıyor" % [r["error"], CameraPresets.FALLBACK])
	preset_name = r["name"]
	apply_state(r["state"], true)
	# Tercih = preset'in K1 ÖNCESİ eğimi (başlangıç eğimi): Home tercihi buna sıfırlar; K1 yükselttiyse zoom-in'de iner.
	_desired_pitch = clampf(float(r["raw_pitch_deg"]), 0.0, envelope.pitch_max_deg)
	preset_applied.emit(preset_name)
	return r["ok"]


func _sanitized(state: CameraState) -> CameraState:
	var s := state.copy()
	s.heading_deg = wrapf(s.heading_deg, 0.0, 360.0)
	return _enforce(s)


## Hedef durumu TERCİH EDİLEN eğimle çözer: pozu çağıran işlem üretir (fiili eğimle), eğim ise `max(tercih, gereken)`.
func _enforce_desired(s: CameraState, mode: StringName = CameraEnvelope.MODE_DEFAULT) -> CameraState:
	var wanted := s.copy()
	wanted.pitch_deg = _desired_pitch
	return _enforce(wanted, mode)


## Zarf + K1 (saf `CameraEnvelope.resolve`); dünya yoksa yalnız uzaklık/eğim sınırları.
func _enforce(s: CameraState, mode: StringName = CameraEnvelope.MODE_DEFAULT) -> CameraState:
	var sea := world.sea_level if world != null else 0.0
	return envelope.resolve(s, _aspect(), _ground(), world_bounds(), mode, sea)


func _aspect() -> float:
	var size := _viewport_size()
	return size.x / size.y


func _update_band() -> void:
	var band := envelope.next_band(_current.distance, scale_band)
	if band != scale_band:
		scale_band = band
		scale_band_changed.emit(band)


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
	var gates := envelope.zoom_gates_m
	var d := _target.distance
	var goal := d
	if factor > 1.0:
		for i in range(gates.size() - 1, -1, -1):
			if gates[i] < d * 0.98:
				goal = gates[i]
				break
		if goal == d:
			goal = gates[0]
	else:
		for gate in gates:
			if gate > d * 1.02:
				goal = gate
				break
		if goal == d:
			goal = gates[gates.size() - 1]
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
