extends Node3D
## T-001 dünya önizleme sahnesi (DEV): WorldData üretir → chunk'lı flat-shaded arazi + su → tek güneş,
## ışık, kamera.
## Açma: tools/godot.sh --path . res://scenes/dev/world_preview.tscn -- --preset=metro  (veya editörde F6).
## Komut satırı (-- sonrası): --preset=metro|bay_west|plain_east|harbor|d5_slopes  --seed=N  --cell=M (hücre m)
## --chunk=N (hücre)
##   (geçersiz değer → net hata + varsayılan; --cell en az 20 m)
##   --exag=K (gölgeleme eğim abartısı) --sun-el=DERECE --sun-az=DERECE --sun-energy=E --ambient=E --no-shadows
##   --stride=N (LOD deneyi)  --markers (D-kodu/saha işaretleri açık başlar)  --no-threads.
##   --preset=metro | district:D4 | street:12500,8300 | street:port | bay_west | plain_east | harbor | d5_slopes
##   (bkz CameraPresets); --heading=D --pitch=D --distance=M (preset'ten sonra kamera geçersiz kılma, capture için)
##   --sweep[=street:port] otomatik yörünge+zoom taraması (metro->ilçe->sokak->ilçe->metro, kareye bağlı; perf için)
##   --sweep-leg=KARE (etap uzunluğu, varsayılan 150) --sweep-hold=KARE (başta metro bekleme, varsayılan 60).
## Tuşlar: F3 işaretleri aç/kapa (varsayılan KAPALI), 1-5 T-001 preset'leri, M metro, T odakta sokak ölçeği.
## Kamera = CameraRig (T-003, src/view/camera/): girdi YALNIZ InputProfile ile. Masaüstü: sol sürükle kaydır, orta tuş
##   sürükle döndür, tekerlek/trackpad kıstır imleçte zoom; WASD/oklar kaydır, Q/E döndür, PageUp/PageDown zoom;
##   R/F eğim (GEÇİCİ). Dokunmatik (`-- --imaro-input-profile=touch`): tek parmak kaydır, iki parmak kıstır/bük.
## HUD yok; sayılar yalnız konsola. Bu sahne simülasyon durumu tutmaz.

const DATA_DIR := "res://data/world/ismeral"
const SUN_ELEVATION_DEG := 38.0
const SUN_AZIMUTH_DEG := 305.0
## --cell alt/üst sınırı (m): 20 m altı örnek sayısını (ve bellek/üretim süresini) makul olmayan düzeye
## taşır.
const MIN_CELL_M := 20.0
const MAX_CELL_M := 2000.0
## Gölge yalnız bu kamera uzaklığının (m) altında açık: kara chunk başına +1 draw call (~+100, metro);
## metro
## uzaklığında (58 km) gölge uzunluğu birkaç piksel olduğundan kazanç yok (eğim gölgelemesi her ölçekte
## var).
const SHADOW_MAX_CAMERA_DISTANCE_M := 30000.0
## Işık tabanı (VIS-01, AD takibi): gölge yüzü/gölge içindeki yüzler siyaha inmesin. Ambient ~2x (eski 0.42),
## güneş
## buna göre kısıldı: güneşe bakan düz zeminin toplam parlaklığı eski dengeye yakın kalır, gölge tabanı
## yaklaşık iki
## katına çıkar (ölçüm: bkz T-001 raporu).
const SUN_ENERGY := 0.7
const AMBIENT_ENERGY := 0.85
## Gölge uzaklığı = kamera uzaklığı x çarpan, [min, max] aralığında. Alt sınır sokak ölçeğinde de gölge verir
## (tek ortogonal harita: 6 km'de ~1,5 m/texel, 500 m'de ~0,12 m/texel); T-001 preset'lerinin hepsi >3,3 km'dedir
## (değişmez: 1,8x ≥ 6000).
const SHADOW_DISTANCE_PER_CAMERA_DISTANCE := 1.8
const SHADOW_MIN_DISTANCE_M := 500.0
const SHADOW_MAX_DISTANCE_M := 140000.0
## Gölge hattı ilk kullanımda ~0,5 sn takılıyor (shader/harita ilk derleme; T-003 ölçümü: tarama 30 km eşiğinden
## geçerken). İlk kareler gölge zorla açılır (açılış yükü içinde derlensin), sonra uzaklık kuralı.
const SHADOW_WARMUP_FRAMES := 3

## Son kurulumun ölçümleri (perf_probe okur): control_ms, generate_ms, terrain (TerrainView.stats), vb.
var build_stats: Dictionary = {}

var _world: WorldData
var _view_root: Node3D
var _terrain: TerrainView
var _camera: CameraRig
var _sweep: CameraSweep = null
var _sweep_frame: int = 0
var _frames_alive: int = 0
var _markers: WorldDebugMarkers
var _sun: DirectionalLight3D
var _args: Dictionary = {}
var _shadows_wanted: bool = true


func _ready() -> void:
	var args := _parse_args()
	_args = args
	_shadows_wanted = not args.has("no-shadows")
	var t0 := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(DATA_DIR)
	var errors := WorldControlData.validate(control)
	if not errors.is_empty():
		push_error("kontrol verisi geçersiz: %s" % ", ".join(errors))
		return
	var t1 := Time.get_ticks_usec()
	var world_seed := _arg_int(args, "seed", int(control["world"]["default_seed"]), -2147483648, 2147483647)
	var overrides := {}
	var cell_m := _arg_float(args, "cell", -1.0, MIN_CELL_M, MAX_CELL_M)
	if cell_m > 0.0:
		overrides["cell_size_m"] = cell_m
	_world = WorldGenerator.generate(control, world_seed, overrides)
	var t2 := Time.get_ticks_usec()

	# Dünya içeriği (arazi, işaretler) tek kökte: kamera origin rebasing'i bu kökü kaydırır (ADR-0002 §2).
	_view_root = Node3D.new()
	_view_root.name = "WorldView"
	add_child(_view_root)
	_terrain = TerrainView.new()
	_terrain.name = "Terrain"
	_terrain.chunk_cells = _arg_int(args, "chunk", _terrain.chunk_cells, 4, 256)
	_terrain.lod_stride = _arg_int(args, "stride", 1, 1, 16)
	_terrain.use_threads = not args.has("no-threads")
	_terrain.shading_exaggeration = _arg_float(args, "exag", _terrain.shading_exaggeration, 0.5, 12.0)
	_terrain.cast_shadows = not args.has("no-shadows")
	_view_root.add_child(_terrain)
	_terrain.build(_world)
	var t3 := Time.get_ticks_usec()

	_setup_environment()
	_setup_sun()
	_markers = WorldDebugMarkers.new()
	_markers.name = "DebugMarkers"
	_view_root.add_child(_markers)
	_markers.build(_world)
	if args.has("markers"):
		_markers.set_markers_visible(true)

	_camera = CameraRig.new()
	_camera.name = "CameraRig"
	_camera.view_root = _view_root
	add_child(_camera)
	_camera.set_world(_world, _terrain.surface_height_at)
	_camera.make_current()
	_camera.apply_preset(str(args.get("preset", "metro")))
	_apply_camera_overrides(args)
	if args.has("sweep"):
		var street_spec := str(args["sweep"]) if str(args["sweep"]) != "true" else "street:port"
		_sweep = CameraSweep.build(_world, street_spec, _terrain.surface_height_at,
				_arg_int(args, "sweep-leg", CameraSweep.DEFAULT_FRAMES_PER_LEG, 2, 100000),
				_arg_int(args, "sweep-hold", CameraSweep.DEFAULT_HOLD_FRAMES, 0, 100000))

	build_stats = {
		"seed": world_seed, "preset": String(_camera.preset_name), "sweep_frames": _sweep.total_frames() if _sweep else 0,
		"world_samples": _world.width * _world.height, "cell_size_m": _world.cell_size,
		"control_load_ms": snappedf((t1 - t0) / 1000.0, 0.1),
		"world_generate_ms": snappedf((t2 - t1) / 1000.0, 0.1),
		"terrain_build_ms": snappedf((t3 - t2) / 1000.0, 0.1),
		"terrain": _terrain.stats,
	}
	print("WORLD_PREVIEW ", JSON.stringify(build_stats))


func _process(_delta: float) -> void:
	if _sweep != null:
		# Kareye bağlı (duvar saati değil): tekrarlanabilir yol. Rig'in yumuşatması atlanır (yol zaten yumuşak).
		_camera.apply_state(_sweep.state_at_frame(_sweep_frame), true)
		_sweep_frame += 1
	if _sun != null and _camera != null:
		# Gölge mesafesi kamera uzaklığına bağlı: yakın planda keskin, metroda geniş ama yine yumuşak.
		_sun.directional_shadow_max_distance = clampf(_camera.distance() * SHADOW_DISTANCE_PER_CAMERA_DISTANCE,
				SHADOW_MIN_DISTANCE_M, SHADOW_MAX_DISTANCE_M)
		_frames_alive += 1
		var warming := _frames_alive <= SHADOW_WARMUP_FRAMES
		_sun.shadow_enabled = _shadows_wanted and (warming or _camera.distance() < SHADOW_MAX_CAMERA_DISTANCE_M)
	if _markers != null and _markers.visible:
		_markers.rescale_for(_camera.camera)


## perf_probe etiketi: tarama sırasında ölçek aşaması (metro/district/local/street), değilse preset adı.
func perf_tag() -> String:
	if _sweep != null and _camera != null:
		return String(CameraSweep.phase_of(_camera.distance()))
	return String(_camera.preset_name) if _camera != null else ""


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	if key.keycode == KEY_F3 and _markers != null:
		_markers.set_markers_visible(not _markers.visible)
		return
	var digit := key.physical_keycode - KEY_1
	if digit >= 0 and digit < CameraPresets.KEY_ORDER.size() and _camera != null:
		_camera.apply_preset(String(CameraPresets.KEY_ORDER[digit]))
	elif key.physical_keycode == KEY_M and _camera != null:
		_camera.apply_preset("metro")
	elif key.physical_keycode == KEY_T and _camera != null:
		var f := _camera.focus_xz()
		_camera.apply_preset("street:%d,%d" % [int(f.x), int(f.y)])


func world() -> WorldData:
	return _world


func camera() -> CameraRig:
	return _camera


func terrain() -> TerrainView:
	return _terrain


## Sayısal komut satırı argümanı: değer yoksa/sayı değilse/aralık dışıysa net hata yazar ve güvenli
## varsayılana döner
## (sıfıra bölme, devasa dünya vb. SCRIPT ERROR yerine). Dönüş: geçerli değer ya da `fallback`.
static func _arg_float(args: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	if not args.has(key):
		return fallback
	var text := str(args[key])
	if not text.is_valid_float():
		push_error("world_preview: --%s='%s' sayı değil; varsayılan (%s) kullanılıyor" % [key, text, fallback])
		return fallback
	var value := text.to_float()
	if value < lo or value > hi:
		push_error("world_preview: --%s=%s aralık dışı [%s, %s]; varsayılan (%s) kullanılıyor"
				% [key, text, lo, hi, fallback])
		return fallback
	return value


static func _arg_int(args: Dictionary, key: String, fallback: int, lo: int, hi: int) -> int:
	if not args.has(key):
		return fallback
	var text := str(args[key])
	if not text.is_valid_int():
		push_error("world_preview: --%s='%s' tam sayı değil; varsayılan (%s) kullanılıyor" % [key, text, fallback])
		return fallback
	var value := text.to_int()
	if value < lo or value > hi:
		push_error("world_preview: --%s=%s aralık dışı [%s, %s]; varsayılan (%s) kullanılıyor"
				% [key, text, lo, hi, fallback])
		return fallback
	return value


## --heading/--pitch/--distance: preset'ten sonra kamerayı anında geçersiz kılar (capture kompozisyonu). Geçersiz
## değer net hata verir ve yok sayılır.
func _apply_camera_overrides(args: Dictionary) -> void:
	if not (args.has("heading") or args.has("pitch") or args.has("distance")):
		return
	var s := _camera.target_state()
	s.heading_deg = _arg_float(args, "heading", s.heading_deg, 0.0, 360.0)
	s.pitch_deg = _arg_float(args, "pitch", s.pitch_deg, CameraMath.MIN_PITCH_DEG, CameraMath.MAX_PITCH_DEG)
	s.distance = _arg_float(args, "distance", s.distance, CameraMath.MIN_DISTANCE_M, CameraMath.MAX_DISTANCE_M)
	_camera.apply_state(s, true)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var body := arg.trim_prefix("--")
		var eq := body.find("=")
		if eq < 0:
			result[body] = true
		else:
			result[body.substr(0, eq)] = body.substr(eq + 1)
	return result


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.06, 0.085)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = _arg_float(_args, "ambient", AMBIENT_ENERGY, 0.0, 2.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


## Tek yönlü güneş: kuzeybatıdan ~40° yükseklik; yamaçların gölge yüzü kameraya (güney/doğu) döner.
## Hafif ve yumuşak
## gölge (low-key; altın saat/sinematik DEĞİL, VIS-01). Gölge ışığı (mat) ambient ile birlikte okunur
## kalır.
func _setup_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Color(1.0, 0.97, 0.90)
	_sun.light_energy = _arg_float(_args, "sun-energy", SUN_ENERGY, 0.0, 4.0)
	_sun.shadow_enabled = _shadows_wanted
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # tek harita: en ucuz (bkz. perf notu)
	_sun.shadow_opacity = 0.55
	_sun.shadow_blur = 2.5
	_sun.shadow_bias = 0.05
	_sun.shadow_normal_bias = 2.0
	_sun.directional_shadow_max_distance = 20000.0
	add_child(_sun)
	# Güneşe doğru bakan yön: kuzeybatı (x: batı −, z: kuzey −), yükseklik SUN_ELEVATION_DEG.
	var el := deg_to_rad(_arg_float(_args, "sun-el", SUN_ELEVATION_DEG, 5.0, 89.0))
	# Azimut: 0 = kuzey, 90 = doğu; 305 = kuzeybatı (batıya yakın).
	var az := deg_to_rad(_arg_float(_args, "sun-az", SUN_AZIMUTH_DEG, 0.0, 360.0))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	_sun.look_at_from_position(to_sun * 1000.0, Vector3.ZERO, Vector3.UP)
