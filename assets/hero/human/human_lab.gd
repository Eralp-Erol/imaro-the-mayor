extends Node3D
## T-059 isolated human-style proposal lab (library only, not the game): same camera and daylight for every asset.
## --asset=block_neutral --view=front|side|back|top|3q --level=lod0|lod1 --distance=<m> --context=compare|street|scale
## compare: the six proposals (A pawn, B block, C facet x neutral/broad) side by side with the same camera.
## street/scale: unchanged hero building (HERO_BUILDING) plus a T-058 bench and bollard beside the three neutral styles.

const ASSETS: Array[String] = [
	"pawn_neutral", "pawn_broad", "block_neutral", "block_broad", "facet_neutral", "facet_broad",
]
const LABELS: Dictionary = {
	"pawn_neutral": "A piyon · nötr", "pawn_broad": "A piyon · geniş",
	"block_neutral": "B blok · nötr", "block_broad": "B blok · geniş",
	"facet_neutral": "C faset · nötr", "facet_broad": "C faset · geniş",
}
const FOV := 40.0
const FIGURE_HEIGHT := 1.75
const HERO_BUILDING := "res://assets/hero/fam/hero_res_mid_a.glb"
const BENCH := "res://assets/hero/furniture/fur_hero_bench_a_lod0.glb"
const BOLLARD := "res://assets/hero/furniture/fur_hero_bollard_a_lod0.glb"

var _args: Dictionary = {}
var _camera: Camera3D
var _size := Vector3(0.7, FIGURE_HEIGHT, 0.4)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	_environment()
	_ground()
	var context := String(_args.get("context", "false"))
	var asset := String(_args.get("asset", "block_neutral"))
	var level := String(_args.get("level", "lod0"))
	if context != "false":
		_context(context, level)
	else:
		_place(asset, level, Vector3.ZERO, 0.0)
		if String(_args.get("view", "front")) != "top":
			_ruler(Vector3(0.82, 0.0, 0.0))
	_camera = Camera3D.new()
	_camera.fov = FOV
	add_child(_camera)
	_frame(context)
	_camera.make_current()
	var title := Label.new()
	if context == "false":
		title.text = "hum_hero_%s_a · %s/%s · 1,75 m ölçek çubuğu · PROPOSED · lab" % [
			asset, _args.get("view", "front"), level]
	else:
		title.text = "bağlam %s · %s · PROPOSED · lab" % [context, level]
	if _args.has("distance"):
		title.text += " · %s m" % _args["distance"]
	title.position = Vector2(18, 16)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)


func _frame(context: String) -> void:
	var view := String(_args.get("view", "front"))
	var tan_half := tan(deg_to_rad(FOV * 0.5))
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / size.y
	var d_v := (FIGURE_HEIGHT * 1.3 * 0.5) / tan_half
	var d_h := ((1.9 + 0.6) * 1.1 * 0.5) / (tan_half * aspect)
	var distance := float(_args.get("distance", maxf(maxf(d_v, d_h), 2.4)))
	var target := Vector3(0.4, FIGURE_HEIGHT * 0.48, 0.0)
	var eye := target + Vector3(0.0, 0.10, 1.0).normalized() * distance
	if context == "compare":
		target = Vector3(0, 0.88, 0)
		if view == "front" or view == "false":
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 3.6
			eye = Vector3(0, 0.88, 30)
		elif view == "side":
			eye = target + Vector3(-1.0, 0.08, 0.0).normalized() * 11.0
		else:
			eye = target + Vector3(0.62, 0.34, 0.85).normalized() * 8.5
	elif context == "street":
		target = Vector3(-0.6, 1.5, 1.0)
		eye = Vector3(3.2, 1.7, 8.6)
	elif context == "scale":
		target = Vector3(0, 7.0, -3)
		eye = Vector3(17, 8.5, 26)
	elif view == "side":
		eye = target + Vector3(-1.0, 0.10, 0.0).normalized() * distance
	elif view == "back":
		eye = target + Vector3(0.0, 0.10, -1.0).normalized() * distance
	elif view == "top":
		eye = target + Vector3(0.0, distance, 0.08)
	elif view == "3q":
		eye = target + Vector3(0.62, 0.34, 0.85).normalized() * distance
	_camera.position = eye
	_camera.look_at(target, Vector3.UP)


func _context(context: String, level: String) -> void:
	if context == "compare":
		# Row axis is perpendicular to the camera view direction: all six figures are equally far from the camera.
		var view := String(_args.get("view", "front"))
		var toward_camera := Vector3(0.0, 0.0, 1.0)
		if view == "side":
			toward_camera = Vector3(-1.0, 0.0, 0.0)
		elif view == "3q":
			toward_camera = Vector3(0.62, 0.0, 0.85).normalized()
		var lateral := Vector3.UP.cross(toward_camera).normalized()
		for i in range(ASSETS.size()):
			var x := float(i / 2 - 1) * 2.4 + (-0.5 if i % 2 == 0 else 0.5)
			_place(ASSETS[i], level, lateral * x, 0.0)
			var label := Label3D.new()
			label.text = LABELS[ASSETS[i]]
			label.font_size = 28
			label.pixel_size = 0.0024
			label.outline_size = 5
			label.modulate = Color(0.12, 0.13, 0.11)
			label.outline_modulate = Color(0.93, 0.92, 0.88)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = lateral * x + toward_camera * 0.6 + Vector3(0.0, -0.18, 0.0)
			add_child(label)
		_ruler(lateral * -3.35)
		return
	var building := (load(HERO_BUILDING) as PackedScene).instantiate() as Node3D
	building.position = Vector3(0, 0, -4)
	add_child(building)
	_scene_prop(BENCH, Vector3(-2.6, 0, 1.0), 0.0)
	_scene_prop(BOLLARD, Vector3(1.9, 0, 1.4), 0.0)
	_place("pawn_neutral", level, Vector3(-0.9, 0, 2.3), 0.0)
	_place("block_neutral", level, Vector3(0.0, 0, 2.3), 0.0)
	_place("facet_neutral", level, Vector3(0.9, 0, 2.3), 0.0)
	_place("block_broad", level, Vector3(-3.5, 0, 2.3), 0.0)


func _scene_prop(path: String, pos: Vector3, yaw_degrees: float) -> void:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = pos
	node.rotation_degrees.y = yaw_degrees
	add_child(node)
	_matte(node)


func _matte(node: Node3D) -> void:
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for i in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if mat:
				mat.roughness = 1.0
				mat.metallic_specular = 0.0
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _place(asset: String, level: String, pos: Vector3, yaw_degrees: float) -> Node3D:
	_scene_prop("res://assets/hero/human/hum_hero_%s_a_%s.glb" % [asset, level], pos, yaw_degrees)
	return get_child(get_child_count() - 1) as Node3D


func _ruler(pos: Vector3) -> void:
	## 1.75 m neutral ruler pole with ticks every 0.5 m (reference, not a model).
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.30)
	mat.roughness = 1.0
	var pole := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.03, FIGURE_HEIGHT, 0.03)
	pole.mesh = box
	pole.material_override = mat
	pole.position = pos + Vector3(0, FIGURE_HEIGHT * 0.5, 0)
	add_child(pole)
	for i in range(4):
		var tick := MeshInstance3D.new()
		var tick_box := BoxMesh.new()
		tick_box.size = Vector3(0.16 if i == 3 else 0.09, 0.012, 0.03)
		tick.mesh = tick_box
		tick.material_override = mat
		tick.position = pos + Vector3(0, 0.5 * float(i + 1) if i < 3 else FIGURE_HEIGHT, 0)
		add_child(tick)


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
	sun.directional_shadow_max_distance = 120.0
	sun.rotation_degrees = Vector3(-38, -35, 0)
	add_child(sun)


func _ground() -> void:
	var node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	node.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/ground/tex/gnd_plaza_stone_a.png")
	mat.uv1_scale = Vector3(30, 30, 30)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	node.material_override = mat
	node.position.y = -0.02
	add_child(node)
