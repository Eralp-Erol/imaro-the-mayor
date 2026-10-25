extends Node3D
## T-055 zemin LAB (DEV, oyuna BAĞLI DEĞİL): 200 m x 200 m yamaçlı arazi parçası; tek malzeme (ground_lab.gdshader).
## Oyunun fam_lab ışığı (güneş 38°, enerji 0,5, ambient 0,7, lineer tonemap).
## Argümanlar: --shot=eye|street|district|metro|plan|plaza|coast|slope  --old=1 (eski tek-renk zemin: önce/sonra kıyas için basit köşe rengi)
const SIZE := 200.0
const STEP := 2.0
const TEX := "res://assets/ground/tex/"
var _args := {}
var _cam: Camera3D
var _noise := FastNoiseLite.new()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			_args[kv[0]] = kv[1]
	_noise.seed = 5500
	_noise.frequency = 0.035
	_env()
	_sun()
	add_child(_terrain())
	_sea()
	_buildings()
	_person(Vector3(-4.0, _h(-4.0, 8.0), 8.0), Color(0.35, 0.40, 0.48))
	_person(Vector3(2.5, _h(2.5, 12.0), 12.5), Color(0.55, 0.30, 0.25))
	_cam = Camera3D.new()
	add_child(_cam)
	_frame(String(_args.get("shot", "street")))


var _fc := 0
var _t0 := 0


func _process(_d: float) -> void:
	if not _args.has("perf"):
		return
	_fc += 1
	if _fc == 60:
		_t0 = Time.get_ticks_usec()
	if _fc == 360:
		var ms := float(Time.get_ticks_usec() - _t0) / 300.0 / 1000.0
		print("PERF avg_frame_ms=%.2f draw_calls=%d vram_MB=%.1f" % [ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
		get_tree().quit()


func _prof(z: float) -> float:
	var pts := [[100.0, -3.0], [62.0, -0.8], [56.0, 0.15], [49.0, 1.5], [41.0, 2.8], [-8.0, 3.2], [-25.0, 4.4], [-48.0, 6.8], [-62.0, 9.0], [-76.0, 14.0], [-100.0, 27.0]]
	for i in range(pts.size() - 1):
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		if z <= a[0] and z >= b[0]:
			var t: float = (a[0] - z) / (a[0] - b[0])
			t = t * t * (3.0 - 2.0 * t) * 0.5 + t * 0.5
			return lerpf(float(a[1]), float(b[1]), t)
	return 27.0 if z < 0.0 else -3.0


func _h(x: float, z: float) -> float:
	var h := _prof(z)
	var terrace := smoothstep(-20.0, 8.0, z) * smoothstep(60.0, 45.0, z)  # kent terası düz
	h += _noise.get_noise_2d(x, z) * 2.4 * (1.0 - terrace * 0.92)
	# doğu kaya çıkıntısı
	var d := Vector2(x - 72.0, z + 38.0).length()
	h += 17.0 * exp(-pow(d / 20.0, 2.0))
	# kıyı kaya burnu (doğu)
	var d2 := Vector2(x - 88.0, z - 52.0).length()
	h += 6.0 * exp(-pow(d2 / 9.0, 2.0))
	return h


func _terrain() -> MeshInstance3D:
	var n := int(SIZE / STEP) + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := []
	for j in range(n):
		for i in range(n):
			hs.append(_h(-100.0 + i * STEP, -100.0 + j * STEP))
	for j in range(n - 1):
		for i in range(n - 1):
			var x0 := -100.0 + i * STEP
			var z0 := -100.0 + j * STEP
			var p00 := Vector3(x0, hs[j * n + i], z0)
			var p10 := Vector3(x0 + STEP, hs[j * n + i + 1], z0)
			var p01 := Vector3(x0, hs[(j + 1) * n + i], z0 + STEP)
			var p11 := Vector3(x0 + STEP, hs[(j + 1) * n + i + 1], z0 + STEP)
			for p in [p00, p10, p01, p10, p11, p01]:
				st.set_smooth_group(0)
				st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _old_mat() if String(_args.get("old", "0")) == "1" else _ground_mat()
	return mi


func _ground_mat() -> ShaderMaterial:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEX + "ground_layers.json"))
	var imgs: Array[Image] = []
	var tiles := PackedFloat32Array()
	for L in meta["layers"]:
		var im := Image.load_from_file(ProjectSettings.globalize_path(TEX + L["file"]))
		im.convert(Image.FORMAT_RGBA8)
		im.generate_mipmaps()
		imgs.append(im)
		tiles.append(float(L["tile_m"]))
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	var mac := Image.load_from_file(ProjectSettings.globalize_path(TEX + "gnd_macro.png"))
	mac.generate_mipmaps()
	var ctrl := Image.load_from_file(ProjectSettings.globalize_path(TEX + "gnd_lab_ctrl.png"))
	ctrl.generate_mipmaps()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/ground/ground_lab.gdshader")
	sm.set_shader_parameter("layers", arr)
	sm.set_shader_parameter("macro_tex", ImageTexture.create_from_image(mac))
	sm.set_shader_parameter("ctrl_tex", ImageTexture.create_from_image(ctrl))
	sm.set_shader_parameter("tile_m", tiles)
	return sm


## Önce/sonra: oyundaki mevcut zemin gibi köşe rengi (düz renk) + yumuşak gölgeleme, doku yok.
func _old_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.58, 0.54, 0.35)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	return m


func _sea() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000, 8000)
	mi.mesh = pm
	mi.position = Vector3(0, -0.15, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.36, 0.46)
	m.roughness = 1.0
	m.metallic_specular = 0.0
	mi.material_override = m
	add_child(mi)


func _buildings() -> void:
	for spec in [["a", -10.0], ["b", -23.5], ["c", 3.5]]:
		var root: Node3D = (load("res://assets/hero/fam/hero_bazaar_%s.glb" % spec[0]) as PackedScene).instantiate()
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
		root.position = Vector3(spec[1], 3.2, -5.9)
		add_child(root)


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
	s.directional_shadow_max_distance = 400.0
	add_child(s)
	var el := deg_to_rad(38.0)
	var az := deg_to_rad(float(_args.get("sun-az", 215.0)))
	s.look_at_from_position(Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * 100.0, Vector3.ZERO, Vector3.UP)


func _box(pos: Vector3, size: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _person(p: Vector3, c: Color) -> void:
	_box(p + Vector3(0, 0.45, 0), Vector3(0.34, 0.9, 0.2), c * 0.8)
	_box(p + Vector3(0, 1.15, 0), Vector3(0.42, 0.55, 0.24), c)
	_box(p + Vector3(0, 1.62, 0), Vector3(0.2, 0.26, 0.2), Color(0.78, 0.60, 0.48))


func _look(from: Vector3, at: Vector3, fov: float) -> void:
	_cam.fov = fov
	_cam.far = 4000.0
	_cam.look_at_from_position(from, at, Vector3.UP)


func _frame(shot: String) -> void:
	match shot:
		"eye":    # insan seviyesi: kaldırımdan meydan/tarla yönüne bakış
			_look(Vector3(-2.0, 3.2 + 1.7, 17.0), Vector3(6.0, 3.2 + 0.2, -2.0), 62.0)
		"street": # sokak: ~9 m yükseklik, yola ve meydana oblik
			_look(Vector3(-52.0, 3.2 + 8.5, 45.0), Vector3(-6.0, 3.2, 14.0), 50.0)
		"plaza":
			_look(Vector3(20.0, 3.2 + 3.0, 34.0), Vector3(-8.0, 3.2, 6.0), 55.0)
		"coast":
			_look(Vector3(20.0, 3.5, 78.0), Vector3(0.0, 1.5, 40.0), 60.0)
		"slope":
			_look(Vector3(-40.0, 14.0, -22.0), Vector3(40.0, 12.0, -80.0), 55.0)
		"district": # ilçe uzaklığı ~100 m
			_look(Vector3(-20.0, 70.0, 108.0), Vector3(0.0, 4.0, -18.0), 40.0)
		"metro":   # metro uzaklığına yakın: yüksek ve uzak (mip/uzak karışım)
			_look(Vector3(-140.0, 420.0, 520.0), Vector3(0.0, 0.0, 0.0), 40.0)
		"plan":
			_look(Vector3(0.0, 330.0, 8.0), Vector3(0.0, 0.0, 0.0), 40.0)
			_cam.rotation_degrees = Vector3(-90, 0, 0)
		_:
			_look(Vector3(-52.0, 12.0, 45.0), Vector3(-6.0, 3.2, 14.0), 50.0)
