extends Node3D
## T-057 mahalle ölçeği laboratuvarı (yalnız lab; oyuna bağlı DEĞİL, hepsi PROPOSED).
## Yeni dokulu hero binalar + T-055 zemin dokuları + T-057 bitki önerileri, ~600 m'lik bir mahalle.
## Tuşlar: 1=150 m  2=300 m  3=900 m  B=uzak temsil (LOD1 / yeşil leke)  ←→ döndür  ↑↓ eğim  +/- mesafe
## Bitki seviyesi AĞACIN KAMERAYA uzaklığına göre (kamera her değiştiğinde yeniden seçilir): <120 m LOD0,
## <lod1_max LOD1, ötesi yeşil leke (karar önizlemesi).
## Argümanlar: --view=300 --lod1_max=400 --seed=7
const SPECIES := ["plane", "olive_open", "olive_twisted", "pine_brutia", "cypress", "palm_date", "palm_slender",
	"maquis", "hedge"]
const SPECIES_WEIGHT := [3, 3, 2, 3, 2, 2, 1, 2, 1]
const BUILDINGS := ["hero_res_mid_a", "hero_res_mid_b", "hero_res_mid_c", "hero_res_late_a", "hero_res_late_b",
	"hero_res_late_c", "hero_house_a", "hero_house_b", "hero_house_c", "hero_bazaar_a", "hero_civic_a",
	"hero_industrial_a"]
const GRID := 17
const CELL := 34.0
const BLOCK := 3
const STREET_W := 9.0
const LOD0_MAX := 120.0

var _args := {}
var _metadata := {}
var _camera: Camera3D
var _label: Label
var _yaw := 35.0
var _pitch := 48.0
var _distance := 300.0
var _far_blob := false
var _lod1_max := 400.0
var _trees := Node3D.new()
var _tree_spots: Array = []
var _scene_cache := {}
var _counts := {"lod0": 0, "lod1": 0, "blob": 0}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	_distance = float(_args.get("view", 300))
	_lod1_max = float(_args.get("lod1_max", 400))
	_far_blob = String(_args.get("far", "lod1")) == "blob"
	_yaw = float(_args.get("yaw", _yaw))
	_pitch = float(_args.get("pitch", _pitch))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	for entry in catalog["entries"]:
		if entry.get("source", {}).get("kind") == "hero_vegetation":
			_metadata[entry["family"].trim_prefix("hero_").trim_suffix("_a")] = entry
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_environment()
	_ground()
	add_child(_trees)
	_buildings_and_spots()
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.far = 6000.0
	add_child(_camera)
	_camera.make_current()
	_label = Label.new()
	_label.position = Vector2(18, 14)
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_update_camera()
	_place_trees()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_distance = 150.0
		KEY_2:
			_distance = 300.0
		KEY_3:
			_distance = 900.0
		KEY_EQUAL, KEY_KP_ADD:
			_distance = maxf(40.0, _distance * 0.85)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_distance = minf(2500.0, _distance / 0.85)
		KEY_LEFT:
			_yaw -= 12.0
		KEY_RIGHT:
			_yaw += 12.0
		KEY_UP:
			_pitch = minf(85.0, _pitch + 6.0)
		KEY_DOWN:
			_pitch = maxf(12.0, _pitch - 6.0)
		KEY_B:
			_far_blob = not _far_blob
	_update_camera()
	_place_trees()


func _update_camera() -> void:
	var dir := Vector3(sin(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)), sin(deg_to_rad(_pitch)),
		cos(deg_to_rad(_yaw)) * cos(deg_to_rad(_pitch)))
	_camera.position = dir * _distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.70, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.55
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 700.0
	sun.rotation_degrees = Vector3(-38, -35, 0)
	add_child(sun)


func _flat(size: Vector2, texture: String, uv: float, pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	node.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ground/tex/" + texture)
	mat.uv1_scale = Vector3(uv, uv, uv)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	node.material_override = mat
	node.position = pos
	add_child(node)


func _ground() -> void:
	_flat(Vector2(5000, 5000), "gnd_grass_dry.png", 900.0, Vector3(0, -0.08, 0))
	var extent := GRID * CELL
	_flat(Vector2(extent, extent), "gnd_dirt_courtyard.png", extent / 4.5, Vector3(0, -0.04, 0))
	var half := extent * 0.5
	for i in range(0, GRID + 1, BLOCK):
		var offset := -half + i * CELL
		_flat(Vector2(STREET_W, extent), "gnd_asphalt_worn.png", extent / 6.0, Vector3(offset, 0.0, 0))
		_flat(Vector2(extent, STREET_W), "gnd_asphalt_worn.png", extent / 6.0, Vector3(0, 0.0, offset))


func _load_scene(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	return _scene_cache[path]


func _buildings_and_spots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_args.get("seed", 7))
	var half := GRID * CELL * 0.5
	for gx in range(GRID):
		for gz in range(GRID):
			var center := Vector3(-half + (gx + 0.5) * CELL, 0, -half + (gz + 0.5) * CELL)
			var on_street := (gx % BLOCK == 0) or (gz % BLOCK == 0)
			var footprint := 0.0
			if not on_street and rng.randf() < 0.85:
				var building := _load_scene("res://assets/hero/fam/%s.glb" % BUILDINGS[rng.randi() % BUILDINGS.size()])
				var node := building.instantiate() as Node3D
				node.position = center
				node.rotation_degrees.y = float(rng.randi() % 4) * 90.0
				add_child(node)
				footprint = _half_extent(node)
			var count := 2 if on_street else 1 + rng.randi() % 2
			for k in range(count):
				var spot := center + Vector3(rng.randf_range(-CELL, CELL) * 0.45, 0, rng.randf_range(-CELL, CELL) * 0.45)
				if on_street:
					spot = center + Vector3(rng.randf_range(-1, 1) * CELL * 0.45, 0, rng.randf_range(-1, 1) * CELL * 0.45)
					var local_x := absf(fmod(spot.x + half, CELL * BLOCK))
					var local_z := absf(fmod(spot.z + half, CELL * BLOCK))
					if local_x > STREET_W * 0.5 + 1.5 and local_x < CELL * BLOCK - STREET_W * 0.5 - 1.5 \
						and local_z > STREET_W * 0.5 + 1.5 and local_z < CELL * BLOCK - STREET_W * 0.5 - 1.5:
						pass
					elif absf(spot.x - center.x) < STREET_W * 0.5 + 0.5 or absf(spot.z - center.z) < STREET_W * 0.5 + 0.5:
						continue
				elif maxf(absf(spot.x - center.x), absf(spot.z - center.z)) < footprint + 2.0:
					continue
				var species := _pick_species(rng)
				_tree_spots.append({"species": species, "pos": spot, "yaw": rng.randf() * 360.0,
					"scale": rng.randf_range(0.9, 1.12)})


func _half_extent(node: Node3D) -> float:
	var extent := 6.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var box := (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
		extent = maxf(extent, maxf(absf(box.position.x - node.global_position.x),
			absf(box.end.x - node.global_position.x)))
		extent = maxf(extent, maxf(absf(box.position.z - node.global_position.z),
			absf(box.end.z - node.global_position.z)))
	return extent


func _pick_species(rng: RandomNumberGenerator) -> String:
	var total := 0
	for weight in SPECIES_WEIGHT:
		total += int(weight)
	var roll := rng.randi() % total
	for i in range(SPECIES.size()):
		roll -= int(SPECIES_WEIGHT[i])
		if roll < 0:
			return SPECIES[i]
	return SPECIES[0]


func _place_trees() -> void:
	for child in _trees.get_children():
		child.queue_free()
	_counts = {"lod0": 0, "lod1": 0, "blob": 0}
	var limit := LOD0_MAX if _far_blob else _lod1_max
	for spot in _tree_spots:
		var pos: Vector3 = spot["pos"]
		var species: String = spot["species"]
		var d := _camera.position.distance_to(pos)
		var node: Node3D
		if d < LOD0_MAX:
			node = _tree("lod0", species)
			_counts["lod0"] += 1
		elif d < limit:
			node = _tree("lod1", species)
			_counts["lod1"] += 1
		else:
			node = _blob(species)
			_counts["blob"] += 1
		node.position = pos
		node.rotation_degrees.y = spot["yaw"]
		node.scale = Vector3.ONE * float(spot["scale"])
		_trees.add_child(node)


func _tree(level: String, species: String) -> Node3D:
	var path := "res://assets/hero/vegetation/veg_hero_%s_a_%s.glb" % [species, level]
	var node := _load_scene(path).instantiate() as Node3D
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.alpha_antialiasing_edge = 0.3
				mat.roughness = 1.0
				mat.metallic_specular = 0.0
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return node


## Karar önizlemesi: uzakta tek tek ağaç yerine ölçülü yeşil leke (gerçek varlık değil, sanat kabulü yok).
func _blob(species: String) -> Node3D:
	var dims: Dictionary = _metadata[species]["dimensions_m"]
	var height := float(dims["height_above_ground"])
	var width := maxf(float(dims["width_x"]), float(dims["depth_z"]))
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.radius = 0.5
	sphere.height = 1.0
	node.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.42, 0.23)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	node.material_override = mat
	var crown_h := height * (0.55 if species.begins_with("palm") or species == "cypress" else 0.6)
	node.scale = Vector3(width * 0.8, crown_h, width * 0.8)
	var holder := Node3D.new()
	node.position = Vector3(0, height - crown_h * 0.5, 0)
	holder.add_child(node)
	return holder


func _process(_delta: float) -> void:
	var mode := "yeşil leke (>%d m)" % int(LOD0_MAX) if _far_blob else "LOD1 (<%d m), ötesi leke" % int(_lod1_max)
	_label.text = "MAHALLE LAB · PROPOSED · oyuna bağlı değil · kamera %d m · uzak: %s\n" % [int(_distance), mode]
	_label.text += "ağaç: %d LOD0 · %d LOD1 · %d leke · %d fps\n" % [_counts["lod0"], _counts["lod1"],
		_counts["blob"], int(Engine.get_frames_per_second())]
	_label.text += "1=150m 2=300m 3=900m · B=uzak temsil · ←→ döndür · ↑↓ eğim · +/- mesafe"
