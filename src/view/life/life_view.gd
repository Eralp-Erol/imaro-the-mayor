class_name LifeView
extends Node3D
## Yaşam belirtisi görünümü (T-050): yol üstünde araçlar, kaldırımda yayalar. Tek dünya: yoğunluk `LifeEdgeActivity`
## (sim verisi) ile belirlenir; bu düğüm YALNIZ okur ve çizer, sim'e yazmaz. Hareket gölgelendiricidedir (kare başı
## CPU örnek güncellemesi yok); CPU işi: kamera yeni bir adım hareket edince hücre aç/kapat + kirli hücre yeniden kur.
##
## LOD/maliyet: hücre (256 m) başına en çok 5 MultiMeshInstance3D (araç; nötr/geniş x LOD0/LOD1). Menzil dışı hücre
## HİÇ kurulmaz (uzaktan görünmez); menzil içinde örnek başına mesafe gölgelendiricide çökertilir. Araç ve insan sayısı
## profil tavanını (`max_cars`/`max_people`) aşarsa uzak hücreler atlanır. Gölge düşürmez (bütçe; sokak seviyesinde
## ışık/gölge sanat kararı AÇIK).

const GROUP_CELL := &"life_cell"

var cfg: LifeConfig = null
var assets: LifeAssets = null
var activity: LifeEdgeActivity = null
var world_seed: int = 0
## Callable(x, z) -> yükseklik (m).
var ground: Callable = Callable()
## Callable(cell: Vector2i) -> bool: hücrenin sim durumu güncel mi (`LifeSimReader.prepare_cell`)? Boşsa hep hazır.
var prepare_cell: Callable = Callable()
## Sayaçlar (perf_probe / test).
var stats: Dictionary = {"cells": 0, "cars": 0, "people": 0, "mmi": 0, "cell_builds": 0, "build_ms_max": 0.0,
		"build_ms_sum": 0.0, "skipped_over_budget": 0, "tris": 0}

var _mat_car: ShaderMaterial = null
var _mat_h0: ShaderMaterial = null
var _mat_h1: ShaderMaterial = null
var _cells: Dictionary = {}
var _skipped: Dictionary = {}
var _car_rows: PackedInt32Array = PackedInt32Array()
var _sidewalks: Dictionary = {}
var _t: float = 0.0
var _running: bool = true
var _cam_render: Vector3 = Vector3.ZERO
var _cam_world: Vector2 = Vector2(1.0e9, 1.0e9)
var _last_step_pos: Vector2 = Vector2(1.0e9, 1.0e9)
var _need_refresh: bool = true
var _waiting: bool = false
var _data_version: int = 0
var _density: float = 1.0
var _car_range: float = 900.0
var _human_range: float = 230.0
var _human_lod0: float = 40.0
var _max_cars: int = 1600
var _max_people: int = 1400
var _per_frame: int = 2
var _tris_car: int = 0
var _tris_h0: int = 0
var _tris_h1: int = 0


func setup(p_cfg: LifeConfig, p_assets: LifeAssets, p_activity: LifeEdgeActivity, p_seed: int,
		p_ground: Callable) -> void:
	cfg = p_cfg
	assets = p_assets
	activity = p_activity
	world_seed = p_seed
	ground = p_ground
	_density = cfg.density()
	_car_range = cfg.profile_value("car_range_m")
	_human_range = cfg.profile_value("human_range_m")
	_human_lod0 = minf(cfg.profile_value("human_lod0_m"), _human_range)
	_max_cars = int(cfg.profile_value("max_cars"))
	_max_people = int(cfg.profile_value("max_people"))
	_per_frame = maxi(1, int(cfg.profile_value("max_cells_built_per_frame")))
	_sidewalks = LifeLayout.sidewalk_table()
	_car_rows = assets.car_rows
	var mv := cfg.data["movement"] as Dictionary
	_mat_car = assets.make_car_material(mv)
	_mat_car.set_shader_parameter("life_range", Vector2(0.0, _car_range))
	_mat_h0 = assets.make_human_material(mv)
	_mat_h0.set_shader_parameter("life_range", Vector2(0.0, _human_lod0))
	_mat_h1 = assets.make_human_material(mv)
	_mat_h1.set_shader_parameter("life_range", Vector2(_human_lod0, _human_range))
	_tris_car = _mesh_tris(assets.car_mesh)
	_tris_h0 = _mesh_tris(assets.human_mesh[0][0])
	_tris_h1 = _mesh_tris(assets.human_mesh[0][1])


func _mesh_tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx != null:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Sim saatini sürer (oyun hızı 0 ise durur). `running` dışarıdan: sim duraklatıldı mı.
func set_running(running: bool) -> void:
	_running = running


func set_time_fixed(seconds: float) -> void:
	_t = seconds
	_apply_time()


func time_seconds() -> float:
	return _t


## Kamera: render uzayı konumu (gölgelendirici mesafesi) ve dünya xz (hücre seçimi).
func track_camera(render_pos: Vector3, world_xz: Vector2) -> void:
	_cam_render = render_pos
	_cam_world = world_xz
	if world_xz.distance_to(_last_step_pos) >= cfg.update_value("camera_step_m"):
		_need_refresh = true


## GLOBAL veri değişti (yol ağı yeniden kuruldu / bölge doluluğu değişti): kurulu TÜM hücreler (kare başına
## `max_cells_built_per_frame`, yakından uzağa) yeniden kurulur. Parsel değişimi yerel kirlenir (`LifeEdgeActivity`).
func mark_data_changed() -> void:
	_data_version += 1


func _process(delta: float) -> void:
	if _running:
		_t += delta
	_apply_time()
	_refresh_cells()


func _apply_time() -> void:
	for mat in [_mat_car, _mat_h0, _mat_h1]:
		(mat as ShaderMaterial).set_shader_parameter("life_t", _t)
		(mat as ShaderMaterial).set_shader_parameter("life_cam", _cam_render)


func _refresh_cells() -> void:
	if activity == null or activity.is_rebuilding():
		return
	var dirty := activity.take_dirty_cells()
	for cell in dirty:
		if _cells.has(cell):
			(_cells[cell] as Dictionary)["dirty"] = true
	if not _need_refresh and dirty.is_empty() and not _waiting and not _has_pending():
		return
	if _need_refresh:
		_last_step_pos = _cam_world
		_skipped.clear()
	_need_refresh = false
	var reach := maxf(_car_range, _human_range) + cfg.update_value("cell_margin_m")
	var cm := activity.cell_m
	var c0 := Vector2i(floori((_cam_world.x - reach) / cm), floori((_cam_world.y - reach) / cm))
	var c1 := Vector2i(floori((_cam_world.x + reach) / cm), floori((_cam_world.y + reach) / cm))
	# 1) Menzil dışına çıkanları kapat.
	var drop: Array = []
	var close_dist := reach + cm
	for cell in _cells:
		var dist_c := _cell_distance(cell)
		var entry := _cells[cell] as Dictionary
		var stale: bool = entry["dirty"] or int(entry["version"]) != _data_version
		if dist_c > close_dist or (stale and dist_c > reach):
			drop.append(cell)
	for cell in drop:
		_free_cell(cell)
	# 2) Menzil içindeki hücreleri (yakından uzağa) kur / kirliyse yeniden kur.
	var want: Array = []
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cell := Vector2i(cx, cz)
			if activity.edges_in_cell(cell).is_empty():
				continue
			var dist := _cell_distance(cell)
			if dist > reach:
				continue
			var entry: Variant = _cells.get(cell)
			if entry == null:
				if _skipped.has(cell):
					continue
				want.append([dist, cell])
			elif (entry as Dictionary)["dirty"] or int((entry as Dictionary)["version"]) != _data_version:
				want.append([dist, cell])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var built := 0
	_waiting = false
	for item in want:
		if built >= _per_frame:
			break
		var cell_i: Vector2i = item[1]
		if prepare_cell.is_valid() and not bool(prepare_cell.call(cell_i)):
			_waiting = true
			continue
		_build_cell(cell_i)
		built += 1
	_update_stats()


func _has_pending() -> bool:
	for cell in _cells:
		var entry := _cells[cell] as Dictionary
		if entry["dirty"] or int(entry["version"]) != _data_version:
			return true
	return false


func _cell_distance(cell: Vector2i) -> float:
	var cm := activity.cell_m
	var cx := (float(cell.x) + 0.5) * cm
	var cz := (float(cell.y) + 0.5) * cm
	# Hücre kutusuna uzaklık (merkez değil): sınırdaki hücre menzile girebilir.
	var dx := maxf(absf(_cam_world.x - cx) - cm * 0.5, 0.0)
	var dz := maxf(absf(_cam_world.y - cz) - cm * 0.5, 0.0)
	return sqrt(dx * dx + dz * dz)


func _free_cell(cell: Vector2i) -> void:
	var entry: Dictionary = _cells.get(cell, {})
	if entry.is_empty():
		return
	var node := entry["node"] as Node3D
	if node != null:
		remove_child(node)
		node.queue_free()
	_cells.erase(cell)


func _build_cell(cell: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	var prev: Dictionary = _cells.get(cell, {})
	var totals := _totals_except(cell)
	var res := LifeLayout.build_cell(activity, cell, world_seed, _density, ground, _car_rows, _sidewalks)
	var counts := res["counts"] as PackedInt32Array
	var cars := counts[LifeLayout.KIND_CAR]
	var people := counts[LifeLayout.KIND_NEUTRAL] + counts[LifeLayout.KIND_BROAD]
	if prev.is_empty() and (totals.x + cars > _max_cars or totals.y + people > _max_people) and _cells.size() > 0:
		_skipped[cell] = true
		stats["skipped_over_budget"] = int(stats["skipped_over_budget"]) + 1
		return
	if not prev.is_empty():
		_free_cell(cell)
	if cars + people == 0:
		_cells[cell] = {"node": null, "version": _data_version, "dirty": false, "cars": 0, "people": 0, "mmi": 0}
		return
	var node := Node3D.new()
	node.name = "LifeCell_%d_%d" % [cell.x, cell.y]
	node.position = Vector3(float(cell.x) * activity.cell_m, 0.0, float(cell.y) * activity.cell_m)
	add_child(node)
	var rows := res["rows"] as Array
	var bounds := res["bounds"] as AABB
	var pad := cfg.layout("max_piece_m") + 20.0
	var aabb := AABB(bounds.position - Vector3(pad, 2.0, pad), bounds.size + Vector3(pad * 2.0, 8.0, pad * 2.0))
	var mmi_count := 0
	var cm := activity.cell_m
	var half_diag := cm * 0.72
	if cars > 0:
		_add_mmi(node, "Cars", assets.car_mesh, _mat_car, rows[LifeLayout.KIND_CAR] as PackedFloat32Array, cars,
				aabb, _car_range + half_diag)
		mmi_count += 1
	for body in 2:
		var kind := LifeLayout.KIND_NEUTRAL + body
		var n := counts[kind]
		if n == 0:
			continue
		_add_mmi(node, "Human%dL0" % body, assets.human_mesh[body][0] as Mesh, _mat_h0,
				rows[kind] as PackedFloat32Array, n, aabb, _human_lod0 + half_diag)
		_add_mmi(node, "Human%dL1" % body, assets.human_mesh[body][1] as Mesh, _mat_h1,
				rows[kind] as PackedFloat32Array, n, aabb, _human_range + half_diag)
		mmi_count += 2
	_cells[cell] = {"node": node, "version": _data_version, "dirty": false, "cars": cars, "people": people,
			"mmi": mmi_count}
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["cell_builds"] = int(stats["cell_builds"]) + 1
	stats["build_ms_sum"] = float(stats["build_ms_sum"]) + ms
	stats["build_ms_max"] = maxf(float(stats["build_ms_max"]), ms)


func _totals_except(skip: Vector2i) -> Vector2i:
	var cars := 0
	var people := 0
	for cell in _cells:
		if cell == skip:
			continue
		cars += int((_cells[cell] as Dictionary)["cars"])
		people += int((_cells[cell] as Dictionary)["people"])
	return Vector2i(cars, people)


func _add_mmi(parent: Node3D, label: String, mesh: Mesh, mat: ShaderMaterial, rows: PackedFloat32Array, count: int,
		aabb: AABB, range_end: float) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = aabb
	for i in count:
		var o := i * LifeLayout.ROW
		var basis := Basis(Vector3.UP, rows[o + 3]).scaled(Vector3.ONE * rows[o + 4])
		mm.set_instance_transform(i, Transform3D(basis, Vector3(rows[o], rows[o + 1], rows[o + 2])))
		mm.set_instance_custom_data(i, Color(rows[o + 5], rows[o + 6], rows[o + 7], rows[o + 8]))
	var inst := MultiMeshInstance3D.new()
	inst.name = label
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.custom_aabb = aabb
	inst.visibility_range_end = range_end
	parent.add_child(inst)


func _update_stats() -> void:
	var cars := 0
	var people := 0
	var mmi := 0
	var tris := 0
	for cell in _cells:
		var e := _cells[cell] as Dictionary
		cars += int(e["cars"])
		people += int(e["people"])
		mmi += int(e["mmi"])
	# Üçgen tahmini: araç + insan (en kötü durum: hepsi LOD1 + LOD0 çifti çizilmez; gölgelendirici çökertir).
	tris = cars * _tris_car + people * (_tris_h0 + _tris_h1)
	stats["cells"] = _cells.size()
	stats["cars"] = cars
	stats["people"] = people
	stats["mmi"] = mmi
	stats["tris_upper_bound"] = tris


## Dev/ölçüm: menzildeki TÜM hücreleri bu karede kur (ısınma / yakalama).
func settle(max_iterations: int = 64) -> void:
	for _i in max_iterations:
		var before := int(stats["cell_builds"])
		_need_refresh = true
		_refresh_cells()
		if int(stats["cell_builds"]) == before:
			break
