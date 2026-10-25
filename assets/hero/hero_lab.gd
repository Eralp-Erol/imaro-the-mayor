extends Node3D
## T-053 hero building lab (DEV, oyuna bağlı değil). Oyunun kit_lab ışığı/ortamı (güneş 38° / 305°, enerji 0,5, ambient 0,7,
## lineer tonemap, Compatibility) ile hero bina varyantlarını gösterir.
## Argümanlar: --shot=front|tq|street_eye|street_game|district|metro|variants  --only=a|b|c
const SUN_ELEVATION_DEG := 38.0
const SUN_AZIMUTH_DEG := 305.0
const SUN_ENERGY := 0.5
const AMBIENT_ENERGY := 0.7
const SPACING := 12.0

var _args := {}
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
	_env()
	_sun()
	_street()
	var only := String(_args.get("only", ""))
	var row := int(_args.get("row", 0))
	if row > 0:
		var order := ["a", "b", "c", "b", "c", "a", "c", "a", "b"]
		for i in range(row):
			var b := _building(order[i % order.size()])
			b.position = Vector3((i - row / 2) * 10.8, 0.0, 0.0)
			add_child(b)
	else:
		var keys: Array = ["a", "b", "c"] if only == "" else [only]
		for k in keys:
			var idx := ["a", "b", "c", "f"].find(k)
			var b2 := _building(k)
			b2.position = Vector3((idx - 1) * SPACING if only == "" else 0.0, 0.0, 0.0)
			add_child(b2)
	_people()
	_cam = Camera3D.new()
	_cam.name = "Camera"
	add_child(_cam)
	_shot(String(_args.get("shot", "tq")))


func _building(k: String) -> Node3D:
	var root: Node3D = (load("res://assets/hero/hero_%s.glb" % k) as PackedScene).instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		for s in range(m.mesh.get_surface_count()):
			var sm := m.mesh.surface_get_material(s)
			if sm is BaseMaterial3D:
				var bm := sm.duplicate() as BaseMaterial3D
				bm.roughness = 1.0
				bm.metallic = 0.0
				bm.metallic_specular = 0.0
				bm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				bm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				m.set_surface_override_material(s, bm)
	return root


func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.70, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = float(_args.get("ambient", AMBIENT_ENERGY))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _sun() -> void:
	var s := DirectionalLight3D.new()
	s.light_color = Color(1.0, 0.97, 0.90)
	s.light_energy = float(_args.get("sun-energy", SUN_ENERGY))
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	s.shadow_opacity = 0.55
	s.shadow_blur = 1.5
	s.shadow_bias = 0.06
	s.shadow_normal_bias = 2.0
	s.directional_shadow_max_distance = 200.0
	add_child(s)
	var el := deg_to_rad(SUN_ELEVATION_DEG)
	var az := deg_to_rad(float(_args.get("sun-az", SUN_AZIMUTH_DEG)))
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	s.look_at_from_position(to_sun * 100.0, Vector3.ZERO, Vector3.UP)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return m


func _box(pos: Vector3, size: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _flat(c)
	mi.position = pos
	add_child(mi)
	return mi


func _street() -> void:
	# +Z yönü cepheye bakar: kaldırım (z 0..3), yol (3..10), karşı kaldırım (10..13); arkada avlu
	_box(Vector3(0, -0.05, 20), Vector3(400, 0.1, 80 + 80), Color(0.70, 0.64, 0.54))      # kent zemini (döşeme/avlu rengi)
	_box(Vector3(0, 0.0, 2.0), Vector3(400, 0.12, 4.0), Color(0.74, 0.70, 0.62))          # kaldırım
	_box(Vector3(0, -0.02, 8.0), Vector3(400, 0.1, 8.0), Color(0.34, 0.33, 0.32))          # asfalt
	_box(Vector3(0, 0.06, 4.1), Vector3(400, 0.18, 0.2), Color(0.62, 0.60, 0.55))          # bordür
	_box(Vector3(0, -0.02, 14.0), Vector3(400, 0.12, 4.0), Color(0.74, 0.70, 0.62))
	_box(Vector3(0, -0.5, -30), Vector3(400, 0.1, 60), Color(0.68, 0.62, 0.52))


func _neighbours() -> void:
	# yalın yer tutucu komşu kütleler (hero DEĞİL): bağlam için
	var cols := [Color(0.80, 0.74, 0.62), Color(0.72, 0.66, 0.60)]
	for i in range(2):
		var sx := (-1.0 if i == 0 else 1.0)
		_box(Vector3(sx * (SPACING * 2.0 + 0.0), 8.0, 5.0), Vector3(9.6, 16.0, 11.0), cols[i])
		_box(Vector3(sx * (SPACING * 3.0), 6.0, 5.0), Vector3(9.6, 12.0, 11.0), cols[1 - i])


func _person(p: Vector3, c: Color) -> void:
	_box(p + Vector3(0, 0.45, 0), Vector3(0.34, 0.9, 0.2), c * 0.8)
	_box(p + Vector3(0, 1.15, 0), Vector3(0.42, 0.55, 0.24), c)
	_box(p + Vector3(0, 1.62, 0), Vector3(0.2, 0.26, 0.2), Color(0.78, 0.60, 0.48))


func _people() -> void:
	_person(Vector3(-2.0, 0.1, 2.4), Color(0.35, 0.40, 0.48))
	_person(Vector3(1.8, 0.1, 3.1), Color(0.55, 0.30, 0.25))


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.fov = fov
	_cam.far = 3000.0
	_cam.near = 0.1
	_cam.look_at_from_position(from, at, Vector3.UP)


func _shot(name: String) -> void:
	var only := String(_args.get("only", ""))
	var cx := 0.0
	match name:
		"front":
			_look(Vector3(cx, 6.3, 34.0), Vector3(cx, 6.3, 0.0), 30.0)
		"front_close":
			_look(Vector3(cx, 3.2, 14.0), Vector3(cx, 3.6, 0.0), 40.0)
		"tq":
			_look(Vector3(cx + 20.0, 11.0, 24.0), Vector3(cx, 6.5, 0.0), 36.0)
		"roof":
			_look(Vector3(cx - 16.0, 22.0, 20.0), Vector3(cx + 1, 11.5, 4.0), 32.0)
		"street_eye":
			_look(Vector3(cx + 7.0, 1.7, 11.0), Vector3(cx - 1.0, 6.0, 0.0), 62.0)
		"street_down":
			_look(Vector3(cx + 14.0, 1.7, 9.0), Vector3(cx - 18.0, 5.0, 0.0), 60.0)
		"street_game":
			# kit_street_close benzeri: pitch 9, uzaklık 26 m, fov 50
			var d := 26.0
			var p := deg_to_rad(9.0)
			var f := Vector3(cx, 3.0, 0.0)
			_look(f + Vector3(sin(deg_to_rad(20.0)) * cos(p), sin(p), cos(deg_to_rad(20.0)) * cos(p)) * d, f, 50.0)
		"district":
			var d2 := 140.0
			var p2 := deg_to_rad(40.0)
			var f2 := Vector3(cx, 4.0, 0.0)
			_look(f2 + Vector3(sin(deg_to_rad(25.0)) * cos(p2), sin(p2), cos(deg_to_rad(25.0)) * cos(p2)) * d2, f2, 40.0)
		"district_near":
			var d3 := 70.0
			var p3 := deg_to_rad(38.0)
			var f3 := Vector3(cx, 4.0, 0.0)
			_look(f3 + Vector3(sin(deg_to_rad(25.0)) * cos(p3), sin(p3), cos(deg_to_rad(25.0)) * cos(p3)) * d3, f3, 40.0)
		"variants":
			_look(Vector3(0.0, 8.0, 52.0), Vector3(0.0, 6.0, 0.0), 40.0)
		_:
			_look(Vector3(20.0, 11.0, 24.0), Vector3(0, 6.5, 0), 36.0)
