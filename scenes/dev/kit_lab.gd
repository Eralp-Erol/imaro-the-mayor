extends Node3D
## T-004 kit_lab (DEV): yapı kiti modülleri + ölçek nesneleri + MultiMesh varyasyon alanı. Sahne tamamen kodla
## kurulur.
## Açma:   tools/godot.sh --path . res://scenes/dev/kit_lab.tscn -- --preset=kit_block
## Preset (spec 9.1): kit_lineup | kit_lineup_left | kit_lineup_right | kit_street | kit_street_close (ek) | kit_block
## | kit_district |
##   kit_roofs | kit_square.
## Bayraklar: --seed=N  --chunk=M (LOD/yığın boyu m, varsayılan 1000 = spec 7.1)  --lod=auto|0|1|proxy  --no-shadows  --all
## (lineup'ı da kur)
##   --no-props  --metrics-out=/abs/x.json  --cam-dist=M --cam-pitch=D --cam-heading=D (preset üstüne kamera).
##   --terrain: T-001 WorldData arazisi (TerrainView, yalnız okunur) üzerinde kit (spec 9.3 Q6 karesi).
##   Kamera: bkz kit_lab_camera.gd. Işık = güneş 38°/305°, 0,5; ortam 0,7 (spec 13 not 3).
## Simülasyon durumu tutmaz; HUD yok. Sayılar konsola (KIT_LAB_METRICS) ve build_stats'a gider.

const SUN_ELEVATION_DEG := 38.0
const SUN_AZIMUTH_DEG := 305.0
const SUN_ENERGY := 0.5   ## art-director (T-004 kapısı B1): kit için 0,5 / 0,7; T-001 tabanı 0,7/0,85 değil
const AMBIENT_ENERGY := 0.7   ## --sun-energy=E / --ambient=E ile deneme için geçersiz kılınabilir
const LOD0_END_M := 650.0
const LOD_MARGIN_M := 50.0
const LINEUP_ORIGIN := Vector3(0.0, 0.0, -1600.0)
const LINEUP_IDS: Array[String] = [
	"bld_res_house_a", "bld_res_old_a", "bld_res_old_a_gf", "bld_res_mid_a", "bld_res_mid_a_gf", "bld_res_late_a",
	"bld_res_late_a_gf", "bld_ind_shed_a", "bld_ind_heritage_a", "prop_chimney", "bld_civ_hall_a",
	"bld_lmk_clocktower", "veg_plane", "veh_car", "prop_human",
]
const LINEUP_GAP_M := 5.0
const ASPHALT := Color(0.40, 0.385, 0.36)
const SIDEWALK := Color(0.69, 0.665, 0.61)
const URBAN_GROUND := Color(0.64, 0.61, 0.54)
const OPEN_GROUND := Color(0.58, 0.54, 0.35)
const PLAZA_PAVING := Color(0.70, 0.66, 0.58)

## Son kurulumun ölçümleri (perf_probe okur).
var build_stats: Dictionary = {}
var terrain_info: Dictionary = {}

var _args: Dictionary = {}
var _lib: KitLibrary
var _mat: ShaderMaterial
var _layout: KitLabLayout
var _camera: KitLabCamera
var _sun: DirectionalLight3D
var _shadows: bool = true
var _lod_mode: String = "auto"
var _chunk_m: float = 1000.0
var _mmi_count: int = 0
var _instance_count: int = 0
var _lineup_items: Array[Dictionary] = []


func _ready() -> void:
	_args = _parse_args()
	_shadows = not _args.has("no-shadows")
	_lod_mode = str(_args.get("lod", "auto"))
	_chunk_m = clampf(float(_args.get("chunk", 1000.0)), 100.0, 2000.0)
	var preset := StringName(str(_args.get("preset", "kit_block")))
	var lineup_only := (str(preset).begins_with("kit_lineup") or str(preset).begins_with("kit_gallery")) \
			and not _args.has("all")
	var t0 := Time.get_ticks_usec()
	_lib = KitLibrary.load_manifest()
	_mat = KitMaterial.create()
	_setup_environment()
	_setup_sun()
	_camera = KitLabCamera.new()
	_camera.name = "KitLabCamera"
	add_child(_camera)
	_camera.make_current()
	var metrics := {}
	if not lineup_only:
		_layout = KitLabLayout.new()
		_layout.generate(_lib, int(_args.get("seed", 20261020)))
		if _args.has("terrain"):
			_build_terrain_context()
		_build_ground()
		_build_neighbourhood()
		metrics = _compute_metrics()
	if lineup_only or _args.has("all"):
		_build_lineup()
	_apply_preset(preset)
	build_stats = {
		"preset": String(preset), "build_ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1),
		"multimesh_instances": _mmi_count, "instances": _instance_count, "chunk_m": _chunk_m,
		"lod_mode": _lod_mode, "shadows": _shadows, "terrain": terrain_info, "metrics": metrics,
	}
	print("KIT_LAB ", JSON.stringify(build_stats))
	var out_path := str(_args.get("metrics-out", ""))
	if out_path != "" and not metrics.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(metrics, "\t"))


func _process(_delta: float) -> void:
	if _sun != null and _camera != null and _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_sun.directional_shadow_max_distance = clampf(_camera.distance * 1.6, 120.0, 6000.0)


# --- kurulum ---------------------------------------------------------------------------------------------

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
	env.background_color = Color(0.70, 0.74, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = float(_args.get("ambient", AMBIENT_ENERGY))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _setup_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_color = Color(1.0, 0.97, 0.90)
	_sun.light_energy = float(_args.get("sun-energy", SUN_ENERGY))
	_sun.shadow_enabled = _shadows
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.shadow_opacity = 0.55
	_sun.shadow_blur = 1.5
	_sun.shadow_bias = 0.06
	_sun.shadow_normal_bias = 2.0
	_sun.directional_shadow_max_distance = 800.0
	add_child(_sun)
	var el := deg_to_rad(SUN_ELEVATION_DEG)
	var az := deg_to_rad(SUN_AZIMUTH_DEG)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	_sun.look_at_from_position(to_sun * 1000.0, Vector3.ZERO, Vector3.UP)


func _apply_preset(preset: StringName) -> void:
	_camera.current_preset = preset
	_apply_preset_base(preset)
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE and (
			_args.has("cam-dist") or _args.has("cam-pitch") or _args.has("cam-heading")):
		_camera.apply_state(_camera.focus, float(_args.get("cam-heading", _camera.heading_deg)),
				float(_args.get("cam-pitch", _camera.pitch_deg)), float(_args.get("cam-dist", _camera.distance)),
				_camera.fov)


func _apply_preset_base(preset: StringName) -> void:
	var square := Vector3(0.0, 4.0, 0.0)
	match preset:
		&"kit_lineup", &"kit_lineup_left", &"kit_lineup_right":
			_apply_lineup_camera(preset)
		&"kit_gallery_left", &"kit_gallery_right", &"kit_gallery":
			_apply_gallery_camera(preset)
		&"kit_street":
			var s := _street_focus()
			_camera.apply_state(s, 90.0, 12.0, 60.0, 50.0)   ## sokak ekseni boyunca (doğuya) bakar
		&"kit_street_close":
			_camera.apply_state(_street_focus(), 100.0, 9.0, 26.0, 50.0)
		&"kit_district":
			_camera.apply_state(Vector3(0.0, 0.0, 0.0), 20.0, 50.0, 2500.0, 40.0)
		&"kit_roofs":
			_camera.apply_state(Vector3(0.0, 0.0, 0.0), 0.0, 90.0, 600.0, 40.0)
		&"kit_square":
			_camera.apply_state(square, 25.0, 25.0, 150.0, 40.0)
		_:
			_camera.apply_state(Vector3(40.0, 0.0, 20.0), 20.0, 40.0, 400.0, 40.0)


## Sokak preset'i: meydana en yakın sokak şeridi; kamera sokak ekseninde, doğuya bakar (iki yanda cepheler).
func _street_focus() -> Vector3:
	if _layout == null or _layout.street_view.is_empty():
		return Vector3.ZERO
	return Vector3(float(_layout.street_view["focus_x"]), 3.0, float(_layout.street_view["z"]))


# --- arazi bağlamı (--terrain) ------------------------------------------------------------------------------

## T-001 dünyasını (WorldData -> TerrainView; yalnız okunur) kurar, kit alanını en düz kara dilimine oturtur.
## Arazi, kit zemininin 0,6 m altına indirilir (kit zemini/sokak z-çakışması olmasın).
func _build_terrain_context() -> void:
	var control := WorldControlData.load_dir("res://data/world/ismeral")
	var world := WorldGenerator.generate(control, int(control["world"]["default_seed"]), {})
	var area := KitLabLayout.AREA
	var best := Vector2.ZERO
	var best_range := INF
	var b := world.bounds()
	var x := b.position.x + area.size.x
	while x < b.end.x - area.size.x:
		var z := b.position.y + area.size.y
		while z < b.end.y - area.size.y:
			var lo := INF
			var hi := -INF
			var ok := true
			for fx in 5:
				for fz in 4:
					var sx := x + area.position.x + area.size.x * fx / 4.0
					var sz := z + area.position.y + area.size.y * fz / 3.0
					if world.is_water(sx, sz) or world.height_at(sx, sz) < 8.0:
						ok = false
						break
					var h := world.height_at(sx, sz)
					lo = minf(lo, h)
					hi = maxf(hi, h)
				if not ok:
					break
			if ok and hi - lo < best_range:
				best_range = hi - lo
				best = Vector2(x, z)
			z += 500.0
		x += 500.0
	var terrain := TerrainView.new()
	terrain.name = "Terrain"
	terrain.cast_shadows = _shadows
	terrain.use_threads = false
	add_child(terrain)
	terrain.build(world)
	var h0 := world.height_at(best.x, best.y)
	terrain.position = Vector3(-best.x, -h0 - 0.6, -best.y)
	terrain_info = {"site": [best.x, best.y], "height_m": snappedf(h0, 0.1), "range_m": snappedf(best_range, 0.1),
			"land_chunks": terrain.stats.get("land_chunks", 0)}


# --- zemin ---------------------------------------------------------------------------------------------

func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not _args.has("terrain"):
		_quad(st, Rect2(-9000.0, -9000.0, 18000.0, 18000.0), -0.4, OPEN_GROUND)
	_quad(st, KitLabLayout.AREA.grow(14.0), -0.2, URBAN_GROUND)
	for s in _layout.streets:
		var z: float = s["z"]
		var x0: float = s["x0"]
		var x1: float = s["x1"]
		_quad(st, Rect2(x0, z - 3.75, x1 - x0, 7.5), -0.05, ASPHALT)
		_quad(st, Rect2(x0, z - 6.0, x1 - x0, 2.25), 0.1, SIDEWALK)
		_quad(st, Rect2(x0, z + 3.75, x1 - x0, 2.25), 0.1, SIDEWALK)
	_quad(st, KitLabLayout.PLAZA, 0.12, PLAZA_PAVING)
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _quad(st: SurfaceTool, r: Rect2, y: float, color: Color) -> void:
	var a := Vector3(r.position.x, y, r.position.y)
	var b := Vector3(r.end.x, y, r.position.y)
	var c := Vector3(r.end.x, y, r.end.y)
	var d := Vector3(r.position.x, y, r.end.y)
	st.set_color(color)
	st.set_normal(Vector3.UP)
	for v in [a, b, c, a, c, d]:   # Godot ön yüz = saat yönü (yukarıdan bakınca)
		st.set_color(color)
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


# --- mahalle (MultiMesh) -----------------------------------------------------------------------------------

func _build_neighbourhood() -> void:
	var root := Node3D.new()
	root.name = "Neighbourhood"
	add_child(root)
	var groups := {}
	for p in _layout.placements:
		_group_add(groups, p, true)
	if not _args.has("no-props"):
		for p in _layout.props:
			_group_add(groups, p, false)
	_group_add(groups, _layout.tower, false)
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var g: Dictionary = groups[k]
		_emit_group(root, g)


func _group_add(groups: Dictionary, p: Dictionary, building: bool) -> void:
	var pos: Vector3 = p["pos"]
	var cx := floori((pos.x - KitLabLayout.AREA.position.x) / _chunk_m)
	var cz := floori((pos.z - KitLabLayout.AREA.position.y) / _chunk_m)
	var key := "%s|%d|%d" % [p["id"], cx, cz]
	if not groups.has(key):
		groups[key] = {"id": p["id"], "entry": p["entry"], "items": [], "building": building}
	(groups[key]["items"] as Array).append(p)


func _emit_group(parent: Node3D, g: Dictionary) -> void:
	var id: String = g["id"]
	var entry: Dictionary = g["entry"]
	var items: Array = g["items"]
	var lods: Dictionary = entry["lods"]
	var kind := str(entry["kind"])
	# LOD0 / LOD1 menzilleri (spec 7.2). Ufak ölçek nesneleri uzakta gizlenir.
	var l0_end := LOD0_END_M
	var l1_end := 0.0
	match id:
		"prop_human":
			l0_end = 420.0
		"veh_car":
			l0_end = 900.0
		"veg_plane":
			l0_end = 600.0
			l1_end = 1800.0
		"bld_lmk_clocktower":
			l0_end = 1200.0
	var has_lod1 := lods.has("LOD1")
	if not has_lod1:
		_emit_mmi(parent, id, "LOD0", items, 0.0, l0_end if kind != "building" else 0.0)
	elif _lod_mode == "proxy" and lods.has("PROXY"):
		_emit_mmi(parent, id, "PROXY", items, 0.0, 0.0)   # HLOD şablonu kontrolü (T-012 birleştirmeden önce)
	elif _lod_mode == "0":
		_emit_mmi(parent, id, "LOD0", items, 0.0, 0.0)
	elif _lod_mode == "1":
		_emit_mmi(parent, id, "LOD1", items, 0.0, l1_end)
	else:
		# Histerezis: ilk görünüm için komşu aralıklar `LOD_MARGIN_M` kadar ÇAKIŞIR (aksi halde marjin bandındaki yapı hiç
		# görünmez); geçiş noktası l0_end'dir, yeni görünür olan ilk anda yalnız biri açılır.
		_emit_mmi(parent, id, "LOD0", items, 0.0, l0_end + LOD_MARGIN_M)
		_emit_mmi(parent, id, "LOD1", items, l0_end - LOD_MARGIN_M, l1_end)


func _emit_mmi(parent: Node3D, id: String, lod: String, items: Array, vis_begin: float, vis_end: float) -> void:
	var mesh := _lib.mesh(id, lod)
	if mesh == null:
		push_error("kit_lab: mesh yok %s/%s" % [id, lod])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		var p: Dictionary = items[i]
		var basis := Basis(Vector3.UP, float(p["rot"])) * Basis.from_scale(p["scale"])
		mm.set_instance_transform(i, Transform3D(basis, p["pos"]))
		mm.set_instance_custom_data(i, KitMaterial.encode_instance(p["wall"], p["roof"], p["accent"], p["bright"]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%s_%d" % [id, lod, _mmi_count]
	mmi.multimesh = mm
	mmi.material_override = _mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if vis_begin > 0.0:
		mmi.visibility_range_begin = vis_begin
		mmi.visibility_range_begin_margin = LOD_MARGIN_M
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end
		mmi.visibility_range_end_margin = LOD_MARGIN_M
	parent.add_child(mmi)
	_mmi_count += 1
	_instance_count += items.size()


# --- lineup ---------------------------------------------------------------------------------------------

func _build_lineup() -> void:
	var root := Node3D.new()
	root.name = "Lineup"
	root.position = LINEUP_ORIGIN
	root.rotation.y = PI   ## ön cephe -Z'ye döner: kamera -Z tarafında, T-001 güneşi (KB) cepheyi aydınlatır
	add_child(root)
	var cursor := 0.0
	var wall_pick := {
		"bld_res_house_a": "W1", "bld_res_old_a": "W2", "bld_res_old_a_gf": "W4", "bld_res_mid_a": "W1",
		"bld_res_mid_a_gf": "W7", "bld_res_late_a": "W5", "bld_res_late_a_gf": "W6", "bld_ind_shed_a": "W12",
		"bld_ind_heritage_a": "W10", "prop_chimney": "W10", "bld_civ_hall_a": "W8", "bld_lmk_clocktower": "W11",
		"veg_plane": "W1", "veh_car": "W5", "prop_human": "W7",
	}
	var roof_pick := {
		"bld_res_house_a": "R4", "bld_res_old_a": "R5", "bld_res_old_a_gf": "R3", "bld_res_mid_a": "R1",
		"bld_res_mid_a_gf": "R2", "bld_res_late_a": "R1", "bld_res_late_a_gf": "R2", "bld_ind_shed_a": "R6",
		"bld_ind_heritage_a": "R5", "prop_chimney": "R2", "bld_civ_hall_a": "R1", "bld_lmk_clocktower": "R8",
		"veg_plane": "P2", "veh_car": "R2", "prop_human": "R2",
	}
	_lineup_items.clear()
	for id in LINEUP_IDS:
		var e := _lib.entry(id)
		var lo: Array = e["aabb_lod0_m"]["min"]
		var hi: Array = e["aabb_lod0_m"]["max"]
		var w: float = float(hi[0]) - float(lo[0])
		var pos := Vector3(cursor - float(lo[0]), 0.0, 0.0)
		var item := {"id": id, "entry": e, "pos": pos, "rot": 0.0, "scale": Vector3.ONE,
				"wall": KitMaterial.row_index(str(wall_pick.get(id, "W1"))),
				"roof": KitMaterial.row_index(str(roof_pick.get(id, "R1"))),
				"accent": KitMaterial.row_index("A1" if id.ends_with("_gf") else "A2"), "bright": 1.0}
		_emit_mmi(root, id, "LOD0", [item], 0.0, 0.0)
		_lineup_items.append({"id": id, "x0": cursor, "x1": cursor + w, "w": w, "h": float(hi[1])})
		var label := Label3D.new()
		label.text = "%s\n%.1f x %.1f m  H %.1f m" % [id.trim_prefix("bld_"), w, float(hi[2]) - float(lo[2]), float(hi[1])]
		label.font_size = 30
		label.pixel_size = 0.04
		label.modulate = Color(0.12, 0.12, 0.12)
		label.position = Vector3(cursor + w / 2.0, -2.6, 2.0)
		label.no_depth_test = true
		root.add_child(label)
		if id.begins_with("bld_") and id != "bld_lmk_clocktower":
			var front_z := float(hi[2]) + 1.6   # ön cephenin (tente dahil) hemen önünde, ölçek okuması için
			_emit_mmi(root, "prop_human", "LOD0", [_human_at(cursor + 1.2, front_z, e)], 0.0, 0.0)
		cursor += w + LINEUP_GAP_M
	_build_lineup_stage(root, cursor)


func _human_at(x: float, z: float, _entry: Dictionary) -> Dictionary:
	return {"id": "prop_human", "entry": _lib.entry("prop_human"), "pos": Vector3(x, 0.0, z), "rot": 0.0,
			"scale": Vector3.ONE, "wall": KitMaterial.row_index("W7"), "roof": KitMaterial.row_index("R2"),
			"accent": 0, "bright": 1.0}


func _build_lineup_stage(root: Node3D, total_w: float) -> void:
	var grid := load("res://assets/shaders/kit_grid.gdshader") as Shader
	var backdrop := MeshInstance3D.new()
	backdrop.name = "GridBackdrop"
	var q := QuadMesh.new()
	q.size = Vector2(total_w + 60.0, 220.0)
	backdrop.mesh = q
	var bm := ShaderMaterial.new()
	bm.shader = grid
	bm.set_shader_parameter("plane_axis", 1)
	backdrop.material_override = bm
	backdrop.position = Vector3(total_w / 2.0, 90.0, -45.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(backdrop)
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "GridFloor"
	var pl := PlaneMesh.new()
	pl.size = Vector2(total_w + 60.0, 100.0)
	floor_mi.mesh = pl
	var fm := ShaderMaterial.new()
	fm.shader = grid
	fm.set_shader_parameter("plane_axis", 0)
	floor_mi.material_override = fm
	floor_mi.position = Vector3(total_w / 2.0, -0.02, 0.0)
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor_mi)
	for hm in [5, 10, 15, 20, 25, 30]:
		var l := Label3D.new()
		l.text = "%d m" % hm
		l.font_size = 40
		l.pixel_size = 0.04
		l.modulate = Color(0.12, 0.12, 0.12)
		l.position = Vector3(-8.0, float(hm), -44.0)
		root.add_child(l)


## 3/4 perspektif galeri (ek preset): çatı/yan cephe biçimlerini okumak için; aynı ışık.
func _apply_gallery_camera(preset: StringName) -> void:
	var from_i := 0
	var to_i := _lineup_items.size() - 1
	if preset == &"kit_gallery_left":
		to_i = 6
	elif preset == &"kit_gallery_right":
		from_i = 7
	var x0: float = _lineup_items[from_i]["x0"]
	var x1: float = _lineup_items[to_i]["x1"]
	var cx := (x0 + x1) / 2.0
	var width := x1 - x0
	_camera.apply_state(LINEUP_ORIGIN + Vector3(-cx, 6.0, 0.0), 160.0, 22.0, width * 0.62 + 18.0, 40.0)


func _apply_lineup_camera(preset: StringName) -> void:
	var from_x := 0.0
	var to_x := 0.0
	for it in _lineup_items:
		to_x = maxf(to_x, float(it["x1"]))
	if preset == &"kit_lineup_left":
		to_x = float(_lineup_items[4]["x1"]) + 3.0
		from_x = -6.0
	elif preset == &"kit_lineup_right":
		from_x = float(_lineup_items[7]["x0"]) - 3.0
	else:
		from_x = -10.0
		to_x += 6.0
	var width := to_x - from_x
	var height := width * 9.0 / 16.0
	var cx := (from_x + to_x) / 2.0
	# Lineup kökü Y ekseninde 180° döndü: yerel x → dünya -x; kamera -Z tarafından +Z'ye bakar.
	_camera.apply_ortho(LINEUP_ORIGIN + Vector3(-cx, height / 2.0 - 5.0, 0.0), height, -120.0)


# --- ölçümler ---------------------------------------------------------------------------------------------

func _compute_metrics() -> Dictionary:
	return KitLabMetrics.full_report(_lib, _layout)
