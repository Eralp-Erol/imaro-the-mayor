extends Node3D
## T-001 dünya önizleme sahnesi (DEV): WorldData üretir → chunk'lı flat-shaded arazi + su → tek güneş, ışık, kamera.
## Açma: tools/godot.sh --path . res://scenes/dev/world_preview.tscn -- --preset=metro  (veya editörde F6).
## Komut satırı (-- sonrası): --preset=metro|bay_west|plain_east|harbor  --seed=N  --cell=M (hücre m)  --chunk=N (hücre)
##   --stride=N (LOD deneyi)  --markers (D-kodu/saha işaretleri açık başlar)  --no-threads.
## Tuşlar: F3 işaretleri aç/kapa (varsayılan KAPALI), 1-4 preset; kamera: bkz world_preview_camera.gd.
## HUD yok; sayılar yalnız konsola. Bu sahne simülasyon durumu tutmaz.

const DATA_DIR := "res://data/world/ismeral"

## Son kurulumun ölçümleri (perf_probe okur): control_ms, generate_ms, terrain (TerrainView.stats), vb.
var build_stats: Dictionary = {}

var _world: WorldData
var _terrain: TerrainView
var _camera: WorldPreviewCamera
var _markers: WorldDebugMarkers
var _sun: DirectionalLight3D


func _ready() -> void:
	var args := _parse_args()
	var t0 := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(DATA_DIR)
	var errors := WorldControlData.validate(control)
	if not errors.is_empty():
		push_error("kontrol verisi geçersiz: %s" % ", ".join(errors))
		return
	var t1 := Time.get_ticks_usec()
	var world_seed := int(args.get("seed", control["world"]["default_seed"]))
	var overrides := {}
	if args.has("cell"):
		overrides["cell_size_m"] = float(args["cell"])
	_world = WorldGenerator.generate(control, world_seed, overrides)
	var t2 := Time.get_ticks_usec()

	_terrain = TerrainView.new()
	_terrain.name = "Terrain"
	_terrain.chunk_cells = int(args.get("chunk", _terrain.chunk_cells))
	_terrain.lod_stride = int(args.get("stride", 1))
	_terrain.use_threads = not args.has("no-threads")
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
	env.ambient_light_energy = 0.36
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


## Tek yönlü güneş: yumuşak, düşük kontrast, gölgesiz (low-key; altın saat DEĞİL).
func _setup_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Color(1.0, 0.97, 0.90)
	_sun.light_energy = 1.25
	_sun.shadow_enabled = false
	add_child(_sun)
	# Güneşe doğru bakan yön: batı-kuzeybatı, ~38° yükseklik.
	var to_sun := Vector3(-0.80, 0.52, -0.28).normalized()
	_sun.look_at_from_position(to_sun * 1000.0, Vector3.ZERO, Vector3.UP)
