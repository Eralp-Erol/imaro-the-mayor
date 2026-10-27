extends Node3D
## T-058 isolated proposal lab (library only, not the game): same camera and daylight for every asset.
## --asset=bench --view=front|side|back|top|3q --level=lod0|lod1 --distance=<m> --context=scale|street|lineup
## Context scenes put the unchanged hero building (HERO_BUILDING) and a 1.75 m figure beside the assets.

const ASSETS: Array[String] = [
	"bench", "bin", "lamp_street", "bollard", "bike_rack", "bus_stop", "planter", "kiosk",
]
const FOV := 40.0
const FIGURE_HEIGHT := 1.75
const HERO_BUILDING := "res://assets/hero/fam/hero_res_mid_a.glb"

var _args: Dictionary = {}
var _camera: Camera3D
var _size := Vector3.ONE


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	_environment()
	_ground()
	var context := String(_args.get("context", "false"))
	var asset := String(_args.get("asset", "bench"))
	var level := String(_args.get("level", "lod0"))
	if context != "false":
		_context(context)
	else:
		var node := _place(asset, level, Vector3.ZERO, 0.0)
		_size = _aabb(node).size
		var view := String(_args.get("view", "front"))
		var half := _size.x * 0.5 + 0.55
		if view == "side":
			_figure(Vector3(0.0, 0.0, _size.z * 0.5 + 0.55))
		elif view == "3q":
			_figure(Vector3(-half, 0.0, 0.0))
		else:
			_figure(Vector3(half, 0.0, 0.0))
	_camera = Camera3D.new()
	_camera.fov = FOV
	add_child(_camera)
	_frame(context)
	_camera.make_current()
	var title := Label.new()
	title.text = "%s · %s/%s · figür 1,75 m · PROPOSED · lab" % [
		("fur_hero_%s_a" % asset) if context == "false" else "context " + context,
		_args.get("view", "front"), level]
	if _args.has("distance"):
		title.text += " · %s m" % _args["distance"]
	title.position = Vector2(18, 16)
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)


func _aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var local := mesh.get_aabb()
		var transformed := (node.global_transform.affine_inverse() * mesh.global_transform) * local
		box = transformed if first else box.merge(transformed)
		first = false
	return box


func _frame(context: String) -> void:
	var view := String(_args.get("view", "front"))
	var height := _size.y
	var width := _size.x
	if view == "side":
		width = _size.z
	elif view == "3q" or view == "top":
		width = maxf(_size.x, _size.z)
	var tan_half := tan(deg_to_rad(FOV * 0.5))
	var aspect := float(get_viewport().get_visible_rect().size.x) / float(get_viewport().get_visible_rect().size.y)
	var d_v := (maxf(height, FIGURE_HEIGHT) * 1.3 * 0.5) / tan_half
	var d_h := ((width + 1.3) * 1.25 * 0.5) / (tan_half * aspect)
	var distance := maxf(maxf(d_v, d_h), 2.4)
	if view == "side":
		distance += _size.x * 0.5
	elif view == "front" or view == "back":
		distance += _size.z * 0.5
	distance = float(_args.get("distance", distance))
	var target := Vector3(0.3, maxf(height, FIGURE_HEIGHT) * 0.48, 0.0)
	var eye := target + Vector3(0.0, 0.10, 1.0).normalized() * distance
	if context == "scale":
		target = Vector3(0, 8.5, -3)
		eye = Vector3(22, 12, 32)
	elif context == "street":
		target = Vector3(1.2, 2.0, 0)
		eye = Vector3(6.0, 2.6, 15)
	elif context == "lineup":
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 14.0
		target = Vector3(0, 3.4, 0)
		eye = Vector3(0, 3.4, 30)
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


func _context(context: String) -> void:
	var building := (load(HERO_BUILDING) as PackedScene).instantiate() as Node3D
	if context == "lineup":
		building.free()
		var x := -10.0
		for name in ASSETS:
			var node := _place(name, "lod0", Vector3.ZERO, 0.0)
			var half := _aabb(node).size.x * 0.5
			x += half
			node.position = Vector3(x, 0, 0)
			var label := Label3D.new()
			label.text = name
			label.font_size = 20
			label.pixel_size = 0.012
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position = Vector3(x, -0.35, 1.2)
			add_child(label)
			x += half + (1.6 if name == "lamp_street" else 1.0)
		_figure(Vector3(-11.4, 0, 0.6))
		return
	building.position = Vector3(0, 0, -4)
	add_child(building)
	var row := [
		["bench", -3.0, 1.2, 0.0], ["bin", -1.6, 1.0, 0.0], ["lamp_street", 5.6, 1.6, 0.0],
		["bollard", 0.0, 2.3, 0.0], ["bike_rack", -5.2, 1.6, 90.0], ["bus_stop", 12.0, 2.0, 0.0],
		["planter", 2.4, 0.9, 0.0], ["kiosk", -10.5, 1.0, 0.0],
	]
	for item in row:
		_place(String(item[0]), "lod0", Vector3(float(item[1]), 0, float(item[2])), float(item[3]))
	_figure(Vector3(0.9, 0, 3.0))
	_size = Vector3(4, 8, 4)


func _place(asset: String, level: String, pos: Vector3, yaw_degrees: float) -> Node3D:
	var path := "res://assets/hero/furniture/fur_hero_%s_a_%s.glb" % [asset, level]
	var node := (load(path) as PackedScene).instantiate() as Node3D
	node.position = pos
	node.rotation_degrees.y = yaw_degrees
	add_child(node)
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
	return node


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


func _figure(pos: Vector3) -> void:
	var node := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.height = FIGURE_HEIGHT
	body.radius = 0.22
	node.mesh = body
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.33, 0.31)
	mat.roughness = 1.0
	node.material_override = mat
	node.position = pos + Vector3(0, FIGURE_HEIGHT * 0.5, 0)
	add_child(node)
