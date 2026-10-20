extends Node3D
## T-001 dünya önizleme sahnesi (DEV): WorldData üretir → chunk'lı flat-shaded arazi + su → tek güneş, ışık, kamera.
## Açma: tools/godot.sh --path . res://scenes/dev/world_preview.tscn -- --preset=metro  (veya editörde F6).
## Komut satırı (-- sonrası): --preset=metro|bay_west|plain_east|harbor|d5_slopes  --seed=N  --cell=M (hücre m)  --chunk=N (hücre)
##   (geçersiz değer → net hata + varsayılan; --cell en az 20 m)
##   --exag=K (gölgeleme eğim abartısı) --sun-el=DERECE --sun-az=DERECE --sun-energy=E --ambient=E --no-shadows
##   --stride=N (LOD deneyi)  --markers (D-kodu/saha işaretleri açık başlar)  --no-threads.
## Tuşlar: F3 işaretleri aç/kapa (varsayılan KAPALI), 1-5 preset; kamera: bkz world_preview_camera.gd.
## HUD yok; sayılar yalnız konsola. Bu sahne simülasyon durumu tutmaz.

const DATA_DIR := "res://data/world/ismeral"
const SUN_ELEVATION_DEG := 38.0
const SUN_AZIMUTH_DEG := 305.0
## --cell alt/üst sınırı (m): 20 m altı örnek sayısını (ve bellek/üretim süresini) makul olmayan düzeye taşır.
const MIN_CELL_M := 20.0
const MAX_CELL_M := 2000.0
## Gölge yalnız bu kamera uzaklığının (m) altında açık: kara chunk başına +1 draw call (~+100, metro); metro
## uzaklığında (58 km) gölge uzunluğu birkaç piksel olduğundan kazanç yok (eğim gölgelemesi her ölçekte var).
const SHADOW_MAX_CAMERA_DISTANCE_M := 30000.0
## Işık tabanı (VIS-01, AD takibi): gölge yüzü/gölge içindeki yüzler siyaha inmesin. Ambient ~2x (eski 0.42), güneş
## buna göre kısıldı: güneşe bakan düz zeminin toplam parlaklığı eski dengeye yakın kalır, gölge tabanı yaklaşık iki
## katına çıkar (ölçüm: bkz T-001 raporu).
const SUN_ENERGY := 0.7
const AMBIENT_ENERGY := 0.85

## Son kurulumun ölçümleri (perf_probe okur): control_ms, generate_ms, terrain (TerrainView.stats), vb.
var build_stats: Dictionary = {}

var _world: WorldData
var _terrain: TerrainView
var _camera: WorldPreviewCamera
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

	_terrain = TerrainView.new()
	_terrain.name = "Terrain"
	_terrain.chunk_cells = _arg_int(args, "chunk", _terrain.chunk_cells, 4, 256)
	_terrain.lod_stride = _arg_int(args, "stride", 1, 1, 16)
	_terrain.use_threads = not args.has("no-threads")
	_terrain.shading_exaggeration = _arg_float(args, "exag", _terrain.shading_exaggeration, 0.5, 12.0)
	_terrain.cast_shadows = not args.has("no-shadows")
	add_child(_terrain)
	_terrain.build(_world)
	var t3 := Time.get_ticks_usec()

	_setup_environment()
	_setup_sun()
	_markers = WorldDebugMarkers.new()
	_markers.name = "DebugMarkers"
	add_child(_markers)
	_markers.build(_world)
	if args.has("markers"):
		_markers.set_markers_visible(true)

	_camera = WorldPreviewCamera.new()
	_camera.name = "PreviewCamera"
	_camera.ground_height = _terrain.surface_height_at
	add_child(_camera)
	_camera.make_current()
	_camera.apply_preset(StringName(args.get("preset", "metro")), _world)

	build_stats = {
		"seed": world_seed, "preset": String(_camera.current_preset),
		"world_samples": _world.width * _world.height, "cell_size_m": _world.cell_size,
		"control_load_ms": snappedf((t1 - t0) / 1000.0, 0.1),
		"world_generate_ms": snappedf((t2 - t1) / 1000.0, 0.1),
		"terrain_build_ms": snappedf((t3 - t2) / 1000.0, 0.1),
		"terrain": _terrain.stats,
	}
	print("WORLD_PREVIEW ", JSON.stringify(build_stats))


func _process(_delta: float) -> void:
	if _sun != null and _camera != null:
		# Gölge mesafesi kamera uzaklığına bağlı: yakın planda keskin, metroda geniş ama yine yumuşak.
		_sun.directional_shadow_max_distance = clampf(_camera.distance * 1.8, 6000.0, 140000.0)
		_sun.shadow_enabled = _shadows_wanted and _camera.distance < SHADOW_MAX_CAMERA_DISTANCE_M
	if _markers != null and _markers.visible:
		_markers.rescale_for(_camera)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3 and _markers != null:
		_markers.set_markers_visible(not _markers.visible)


func world() -> WorldData:
	return _world


func camera() -> WorldPreviewCamera:
	return _camera


func terrain() -> TerrainView:
	return _terrain


## Sayısal komut satırı argümanı: değer yoksa/sayı değilse/aralık dışıysa net hata yazar ve güvenli varsayılana döner
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


## Tek yönlü güneş: kuzeybatıdan ~40° yükseklik; yamaçların gölge yüzü kameraya (güney/doğu) döner. Hafif ve yumuşak
## gölge (low-key; altın saat/sinematik DEĞİL, VIS-01). Gölge ışığı (mat) ambient ile birlikte okunur kalır.
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
