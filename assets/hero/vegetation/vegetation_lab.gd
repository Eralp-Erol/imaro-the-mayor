extends Node3D
## T-057 isolated proposal lab: --asset=olive_open --view=front|side|top|detail
## --level=lod0|lod1|proxy --context=true|street|slope|lineup --aa=coverage|off
## All detail levels use measured LOD0 framing. AA choice is lab-only.
const SPECIES := ["plane", "palm_date", "palm_slender", "pine_brutia", "pine_stone",
	"olive_open", "olive_twisted", "cypress", "maquis", "hedge"]
var _args := {}
var _camera: Camera3D
var _metadata := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	for entry in catalog["entries"]:
		if entry.get("source", {}).get("kind") == "hero_vegetation":
			_metadata[entry["family"].trim_prefix("hero_")] = entry
	_environment()
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if _args.get("aa", "coverage") == "off" else Viewport.MSAA_4X
	_ground()
	var context := String(_args.get("context", "false"))
	if context != "false":
		_context(context)
	else:
		_plant(String(_args.get("asset", "olive_open")), String(_args.get("level", "lod0")), Vector3.ZERO)
		_person(Vector3(-float(_metadata[_args.get("asset", "olive_open")]["dimensions_m"]["width_x"]) * 0.5 - 0.8, 0, 1.2))
	_camera = Camera3D.new()
	_camera.fov = 40.0
	add_child(_camera)
	_frame(context)
	_camera.make_current()
	var title := Label.new()
	var asset := String(_args.get("asset", "olive_open"))
	var ident := "veg_hero_%s_a / %.2f m" % [asset, float(_metadata[asset]["dimensions_m"]["height_above_ground"])]
	title.text = "%s · %s/%s · %s · figür 1,75 m · PROPOSED" % [
		context if context != "false" else ident, _args.get("view", "front"), _args.get("level", "lod0"),
		"SCISSOR / NO MSAA" if _args.get("aa", "coverage") == "off" else "4x MSAA / coverage (lab)"]
	if _args.has("distance"):
		title.text += " · %s m" % _args["distance"]
	title.position = Vector2(18, 16)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)


func _frame(context: String) -> void:
	var asset := String(_args.get("asset", "olive_open"))
	var dims: Dictionary = _metadata[asset]["dimensions_m"]
	var height := float(dims["height_above_ground"])
	var width := maxf(float(dims["width_x"]), float(dims["depth_z"]))
	var distance := maxf(maxf(height * 1.85, width * 2.1), 7.0)
	distance = float(_args.get("distance", distance))
	var target := Vector3(0, height * 0.48, 0)
	var eye := target + Vector3(0.55, 0.17, 0.85).normalized() * distance
	if context == "true":
		target = Vector3(-2, 7, -4)
		eye = Vector3(23, 17, 34)
	elif context == "street":
		target = Vector3(-2, 7, -4)
		eye = Vector3(27, 20, 43)
	elif context == "slope":
		target = Vector3(0, 6, 0)
		eye = Vector3(28, 20, 42)
	elif context == "lineup":
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 44
		target = Vector3(0, 6, 0)
		eye = Vector3(0, 17, 70)
	elif _args.get("view", "front") == "side":
		eye = target + Vector3(-1, 0.17, 0.1).normalized() * distance
	elif _args.get("view", "front") == "top":
		eye = target + Vector3(0.1, float(_args.get("distance", maxf(width * 2.5, 12.0))), 0.1)
	elif _args.get("view", "front") == "detail":
		target = Vector3(0, height * 0.65, 0)
		eye = target + Vector3(9, 3, 11)
	_camera.position = eye
	_camera.look_at(target, Vector3.UP)


func _context(context: String) -> void:
	if context == "lineup":
		for i in range(SPECIES.size()):
			var pos := Vector3((i - 4.5) * 8, 0, 0)
			_plant(SPECIES[i], "lod0", pos)
			var label := Label3D.new()
			label.text = SPECIES[i]
			label.font_size = 22
			label.pixel_size = 0.015
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = pos + Vector3(0, 0.3, 3)
			add_child(label)
		_person(Vector3(-42, 0, 3))
		return
	if context == "slope":
		for item in [["pine_stone", -8, -3], ["pine_brutia", 1, -7],
			["olive_twisted", 8, 3], ["cypress", -3, 6], ["maquis", 4, 7]]:
			_plant(item[0], "lod0", Vector3(item[1], -tan(deg_to_rad(8.0)) * float(item[1]), item[2]))
		var house := (load("res://assets/hero/fam/hero_house_a.glb") as PackedScene).instantiate() as Node3D
		house.position = Vector3(-1, 0, -16)
		add_child(house)
	else:
		_plant("olive_open", "lod0", Vector3(-4, 0, 1))
		_plant("palm_date", "lod0", Vector3(4, 0, -1))
		if context == "street":
			_plant("plane", "lod0", Vector3(-11, 0, 2))
			_plant("palm_slender", "lod0", Vector3(10, 0, -7))
			_plant("hedge", "lod0", Vector3(1, 0, 7))
			_plant("maquis", "lod0", Vector3(-5, 0, 7))
		var building := (load("res://assets/hero/fam/hero_res_mid_a.glb") as PackedScene).instantiate() as Node3D
		building.position = Vector3(-11, 0, -11)
		add_child(building)
	_person(Vector3(0, 0, 3))


func _plant(asset: String, level: String, pos: Vector3) -> void:
	var path := "res://assets/hero/vegetation/veg_hero_%s_a_%s.glb" % [asset, level]
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = pos
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
				if _args.get("aa", "coverage") != "off":
					mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				mat.alpha_antialiasing_edge = 0.3
				mat.roughness = 1.0
				mat.metallic_specular = 0.0
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	add_child(node)


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
	sun.directional_shadow_max_distance = 180.0
	sun.rotation_degrees = Vector3(-38, -35, 0)
	add_child(sun)


func _ground() -> void:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	node.mesh = plane
	var mat := StandardMaterial3D.new()
	var slope := String(_args.get("context", "false")) == "slope"
	var texture_path := "gnd_grass_dry.png" if slope else "gnd_dirt_courtyard.png"
	mat.albedo_texture = load("res://assets/ground/tex/" + texture_path)
	mat.uv1_scale = Vector3(22, 22, 22)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	node.material_override = mat
	node.position.y = -0.04
	if slope:
		node.rotation_degrees.z = -8
	add_child(node)


func _person(pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.height = 1.75
	body.radius = 0.22
	node.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.33, 0.31)
	mat.roughness = 1.0
	node.material_override = mat
	node.position = pos + Vector3(0, 0.875, 0)
	add_child(node)


func _process(delta: float) -> void:
	if _args.get("benchmark", "false") != "true":
		return
	if not has_meta("samples"):
		set_meta("samples", [])
		set_meta("warmup", 0)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var warmup := int(get_meta("warmup")) + 1
	set_meta("warmup", warmup)
	if warmup <= 60:
		return
	var samples: Array = get_meta("samples")
	samples.append(delta * 1000.0)
	if samples.size() < 180:
		return
	var total := 0.0
	for sample in samples:
		total += float(sample)
	samples.sort()
	print("VEGETATION_BENCH ", JSON.stringify({
		"context": _args.get("context", "street"), "aa": _args.get("aa", "coverage"),
		"samples": samples.size(), "mean_ms": total / samples.size(),
		"p95_ms": samples[int(samples.size() * 0.95)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"gpu": RenderingServer.get_video_adapter_name(),
		"scope": "isolated library lab, not production city",
	}))
	get_tree().quit()
