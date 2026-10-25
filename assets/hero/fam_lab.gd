extends Node3D
## T-054 hero family lab (DEV, oyuna bağlı değil). Oyunun kit_lab ışığı (güneş 38°, enerji 0,5, ambient 0,7, lineer tonemap).
## Argümanlar: --fam=bazaar|res_mid|res_late|house|industrial|civic  --shot=tq|variants|street|district|district_far  --only=a|b|c
##             --setback=M (cepheden sokağa boşluk)  --sun-az=DERECE (varsayılan 215: cephe aydınlık)
var _args := {}
var _cam: Camera3D
var _bounds := AABB()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
	var fam := String(_args.get("fam", "bazaar"))
	var setback := float(_args.get("setback", 0.0))
	_env()
	_sun()
	var probe := _building(fam, "a")
	_bounds = _aabb(probe)
	probe.free()
	var shot := String(_args.get("shot", "tq"))
	var width := _bounds.size.x + (3.0 if fam != "house" else 2.0)
	var order := ["a", "b", "c", "b", "c", "a", "c"]
	var n := 1
	var keys: Array = [String(_args.get("only", "a"))]
	match shot:
		"variants":
			n = 3
			keys = ["a", "b", "c"]
		"street":
			n = 5
			keys = order.slice(0, 5)
		"district", "district_far":
			n = 7
			keys = order
	for i in range(n):
		var b := _building(fam, keys[i % keys.size()])
		b.position = Vector3((i - (n - 1) * 0.5) * width, 0.0, 0.0)
		add_child(b)
	_street(setback)
	_person(Vector3(-4.0, 0.1, setback + 1.6), Color(0.35, 0.40, 0.48))
	_person(Vector3(3.2, 0.1, setback + 2.4), Color(0.55, 0.30, 0.25))
	_cam = Camera3D.new()
	add_child(_cam)
	_frame(shot, width, n, setback)


func _aabb(root: Node) -> AABB:
	var res := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var bb := m.global_transform * m.get_aabb()
		res = bb if first else res.merge(bb)
		first = false
	return res


func _building(fam: String, k: String) -> Node3D:
	var root: Node3D = (load("res://assets/hero/fam/hero_%s_%s.glb" % [fam, k]) as PackedScene).instantiate()
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
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _sun() -> void:
	var s := DirectionalLight3D.new()
	s.light_color = Color(1.0, 0.97, 0.90)
	s.light_energy = 0.5
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	s.shadow_opacity = 0.55
	s.shadow_blur = 1.5
	s.shadow_bias = 0.06
	s.shadow_normal_bias = 2.0
	s.directional_shadow_max_distance = 300.0
	add_child(s)
	var el := deg_to_rad(38.0)
	var az := deg_to_rad(float(_args.get("sun-az", 215.0)))
	s.look_at_from_position(Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * 100.0, Vector3.ZERO, Vector3.UP)


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	return m


func _box(pos: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _flat(c)
	mi.position = pos
	add_child(mi)


func _street(sb: float) -> void:
	_box(Vector3(0, -0.05, 20), Vector3(500, 0.1, 160), Color(0.70, 0.64, 0.54))
	_box(Vector3(0, 0.0, sb + 2.0), Vector3(500, 0.12, 4.0), Color(0.74, 0.70, 0.62))
	_box(Vector3(0, -0.02, sb + 8.0), Vector3(500, 0.1, 8.0), Color(0.34, 0.33, 0.32))
	_box(Vector3(0, 0.06, sb + 4.1), Vector3(500, 0.18, 0.2), Color(0.62, 0.60, 0.55))
	_box(Vector3(0, 0.0, sb + 14.0), Vector3(500, 0.12, 4.0), Color(0.74, 0.70, 0.62))
	_box(Vector3(0, -0.5, -40), Vector3(500, 0.1, 80), Color(0.68, 0.62, 0.52))


func _person(p: Vector3, c: Color) -> void:
	_box(p + Vector3(0, 0.45, 0), Vector3(0.34, 0.9, 0.2), c * 0.8)
	_box(p + Vector3(0, 1.15, 0), Vector3(0.42, 0.55, 0.24), c)
	_box(p + Vector3(0, 1.62, 0), Vector3(0.2, 0.26, 0.2), Color(0.78, 0.60, 0.48))


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.fov = fov
	_cam.far = 3000.0
	_cam.look_at_from_position(from, at, Vector3.UP)


func _frame(shot: String, width: float, n: int, sb: float) -> void:
	var h := _bounds.size.y
	var l := maxf(_bounds.size.x, h)
	match shot:
		"tq":
			_look(Vector3(0.75 * l, 0.42 * h + 1.5, 1.45 * l + sb), Vector3(0, 0.45 * h, 0.2 * _bounds.size.z), 36.0)
		"variants":
			var half := width * n * 0.5
			_look(Vector3(0, 0.5 * h + 1.0, half / 0.637 * 1.02 + sb), Vector3(0, 0.45 * h, 0), 40.0)
		"street":
			var d := maxf(30.0, 1.9 * h + 8.0)
			var p := deg_to_rad(9.0)
			_look(Vector3(sin(deg_to_rad(20.0)) * cos(p), sin(p), cos(deg_to_rad(20.0)) * cos(p)) * d + Vector3(0, 3.0, sb), Vector3(0, 0.35 * h, 0), 50.0)
		"street_eye":
			_look(Vector3(0.5 * width, 1.7, sb + 12.0), Vector3(-0.2 * width, 0.5 * h, 0), 62.0)
		"district":
			var d2 := maxf(75.0, 4.0 * h)
			var p2 := deg_to_rad(38.0)
			_look(Vector3(sin(deg_to_rad(25.0)) * cos(p2), sin(p2), cos(deg_to_rad(25.0)) * cos(p2)) * d2 + Vector3(0, 3.0, sb), Vector3(0, 0.3 * h, 0), 40.0)
		"district_far":
			var d3 := maxf(150.0, 8.0 * h)
			var p3 := deg_to_rad(40.0)
			_look(Vector3(sin(deg_to_rad(25.0)) * cos(p3), sin(p3), cos(deg_to_rad(25.0)) * cos(p3)) * d3 + Vector3(0, 3.0, sb), Vector3(0, 0.3 * h, 0), 40.0)
		_:
			_look(Vector3(20, 11, 24), Vector3(0, 6.5, 0), 36.0)
