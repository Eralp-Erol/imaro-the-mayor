class_name BuildingView
extends Node3D
## BuildingColumns -> dünyada yapılar (T-012; VIS-02/03/04, TEK-03, TEK-05). Sim'den YALNIZ okur (BuildingColumns); sim
## durumuna yazmaz. Tek dünya: tüm ölçekler aynı sütunlardan çizer, LOD yalnız temsili değiştirir (WLD-01).
##
## Düğüm yapısı (WorldView altına eklenir: origin rebasing otomatik, ADR-0002 §2): her hücre (chunk) için `Cell_x_z`
## Node3D (dünya konumunda) -> modül başına LOD0 ve LOD1 MultiMeshInstance3D + `HLOD1` (birleşik PROXY mesh);
## süper-chunk başına `Super_x_z` HLOD2 MeshInstance3D. Kademe aralıkları BuildingLod (margin'li, çakışan).
##
## Veri akışı: `set_columns(cols, version)` -> doğrula -> chunk planı -> hücre özetleri -> yalnız DEĞİŞEN hücreler
## (ve içerdikleri süper-chunk'lar) yeniden kurulur. Mesh VERİSİ iş parçacıklarında (BuildingChunkBuilder, saf);
## MultiMesh/ArrayMesh/düğüm kurulumu ana iş parçacığında. Yükseklik `WorldData.height_at`'ten (BuildingGround).
##
## Gerçek kaynağa geçiş noktası: `set_columns()` parametresi. Stand-in (`DevBuildingSource`) ile gerçek üretici
## (`T0Settlement.generate`) AYNI `BuildingColumns` türünü verir; değişen tek yer çağıran koddur.

signal cells_rebuilt(keys: Array)

const SUPER_PREFIX := "Super_"
const TRIS_META := &"tris"

## Son kurulumun ölçümleri (perf_probe / world_preview okur).
var stats: Dictionary = {}
var config: BuildingViewConfig = BuildingViewConfig.new()

var _world: WorldData = null
var _kit: BuildingKit = null
var _cols: BuildingColumns = null
var _plan: BuildingChunkPlan = null
var _hashes: Dictionary = {}
var _version: int = -1
var _cell_nodes: Dictionary = {}
var _cell_data: Dictionary = {}
var _dropped: Dictionary = {}
var _super_nodes: Dictionary = {}
var _mat: ShaderMaterial = null
var _proxy_mat: ShaderMaterial = null
# iş parçacığı görev girdileri (set_columns sırasında geçerli)
var _job_keys: Array[Vector2i] = []
var _job_cells: Array[BuildingCellData] = []


## Dünya + kit ile hazırlar (mevcut içerik silinir).
func setup(world: WorldData, kit: BuildingKit, p_config: BuildingViewConfig = null) -> void:
	clear()
	_world = world
	_kit = kit
	if p_config != null:
		config = p_config
	_mat = KitMaterial.create()
	_proxy_mat = KitMaterial.create_proxy()


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cell_nodes.clear()
	_cell_data.clear()
	_dropped.clear()
	_super_nodes.clear()
	_hashes = {}
	_plan = null
	_cols = null
	_version = -1
	stats = {}


## Sütunları gösterir. Yalnız içeriği değişen hücreler yeniden kurulur. `version` >= 0 ve önceki çağrıyla aynı
## (aynı nesne) ise hiçbir şey yapılmaz. Dönüş raporu: {ok, errors, skipped, cells, rebuilt, supers_rebuilt, ...}.
func set_columns(cols: BuildingColumns, version: int = -1) -> Dictionary:
	if _world == null or _kit == null:
		return {"ok": false, "errors": ["BuildingView.setup() çağrılmadı"]}
	var errs := BuildingInputCheck.errors(cols, _kit.count)
	if not errs.is_empty():
		stats["rejected_errors"] = Array(errs)   # günlük çağırana ait; görüntü değişmez
		return {"ok": false, "errors": Array(errs)}
	if version >= 0 and version == _version and cols == _cols:
		return {"ok": true, "skipped": true, "rebuilt": 0, "cells": _cell_nodes.size()}
	var t0 := Time.get_ticks_usec()
	var new_plan := BuildingChunkPlan.build(cols, _world.origin, config.cell_m, config.super_cells)
	var new_hashes := new_plan.cell_hashes(cols)
	var changed := BuildingChunkPlan.changed_cells(_hashes, new_hashes)
	var t1 := Time.get_ticks_usec()
	_cols = cols
	_plan = new_plan
	_version = version
	# değişmeyen hücrelerin sütun indeksleri yeni plana bağlanır
	for k: Vector2i in _cell_data:
		if new_hashes.has(k) and _hashes.get(k, "") == new_hashes[k]:
			(_cell_data[k] as BuildingCellData).rebind(new_plan)
	_hashes = new_hashes
	var supers := _rebuild_cells(changed)
	var t2 := Time.get_ticks_usec()
	_refresh_stats()
	stats["last_plan_ms"] = snappedf((t1 - t0) / 1000.0, 0.1)
	stats["last_build_ms"] = snappedf((t2 - t1) / 1000.0, 0.1)
	stats["last_rebuilt_cells"] = changed.size()
	cells_rebuilt.emit(changed)
	return {"ok": true, "skipped": false, "cells": new_plan.cells.size(), "rebuilt": changed.size(),
			"rebuilt_keys": changed, "supers_rebuilt": supers.size(), "plan_ms": stats["last_plan_ms"],
			"build_ms": stats["last_build_ms"], "errors": []}


## Yükseklik: görünümün kullandığı veri (WorldData.height_at; arazi mesh'i ile aynı kaynak).
func height_at(x: float, z: float) -> float:
	return _world.height_at(x, z) if _world != null else 0.0


func building_count() -> int:
	return _cols.count if _cols != null else 0


func plan() -> BuildingChunkPlan:
	return _plan


func cell_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in _cell_nodes:
		out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


func cell_node(key: Vector2i) -> Node3D:
	return _cell_nodes.get(key) as Node3D


func super_node(skey: Vector2i) -> MeshInstance3D:
	return _super_nodes.get(skey) as MeshInstance3D


func super_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in _super_nodes:
		out.append(k)
	return out


func cell_summary(key: Vector2i) -> BuildingCellData:
	return _cell_data.get(key) as BuildingCellData


## Kamera çocuğu olarak ilk karelerde her gölge/malzeme varyantını çizdirir: shader/gölge hattı açılışta derlenir,
## ilk yakınlaşmada ~0,5 sn takılmaz (T-003 ölçüm bulgusu). Düğümler `frames` kare sonra kendini siler.
func warm_up(camera: Camera3D, frames: int = 3) -> void:
	if _kit == null or camera == null or not is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "BuildingWarmup"
	camera.add_child(root)
	var ahead := -(camera.near + 1.0) * 2.0
	for m in _kit.count:
		if _kit.kinds[m] != "building" or not _kit.has_lod1[m] == 1:
			continue
		for lod in ["LOD0", "LOD1"]:
			var mesh := _kit.mesh(m, lod)
			if mesh == null:
				continue
			var mmi := _make_mmi(mesh, 1)
			mmi.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.001),
					Vector3(0.0, 0.0, ahead)))
			mmi.multimesh.set_instance_custom_data(0, Color(0.0, 0.0, 0.0, 1.0 / 32.0))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod == "LOD0" \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
		break
	var mi := _make_mesh_instance(PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]),
			PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
			PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
	mi.scale = Vector3.ONE * 0.001
	mi.position = Vector3(0.0, 0.0, ahead)
	root.add_child(mi)
	for f in frames:
		await get_tree().process_frame
	if is_instance_valid(root):
		root.queue_free()


# --- özel -----------------------------------------------------------------------------------------------------

## Verilen hücreleri (ve içerdikleri süper-chunk'ları) kurar; silinen hücrelerin düğümlerini kaldırır.
## Dönüş: yeniden kurulan süper-chunk anahtarları.
func _rebuild_cells(changed: Array[Vector2i]) -> Array[Vector2i]:
	var affected_supers: Dictionary = {}
	var to_build: Array[Vector2i] = []
	for k in changed:
		affected_supers[_plan.super_of(k)] = true
		if _plan.cells.has(k):
			to_build.append(k)
		else:
			_remove_cell(k)
	_job_keys = to_build
	_job_cells = []
	_job_cells.resize(to_build.size())
	if config.use_threads and to_build.size() > 1:
		var group := WorkerThreadPool.add_group_task(_cell_task, to_build.size(), -1, true, "building cells")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for n in to_build.size():
			_cell_task(n)
	for n in to_build.size():
		_install_cell(_job_cells[n])
	_job_cells = []
	_job_keys = []
	var supers: Array[Vector2i] = []
	for sk: Vector2i in affected_supers:
		supers.append(sk)
	supers.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if config.build_hlod2:
		_rebuild_supers(supers)
	return supers


func _cell_task(n: int) -> void:
	_job_cells[n] = BuildingChunkBuilder.build_cell(_cols, _plan, _job_keys[n], _kit, _world, config)


func _rebuild_supers(supers: Array[Vector2i]) -> void:
	# süper-chunk -> hücreler eşlemesi her görevde yeniden hesaplanmasın (salt okunur önbellek)
	var groups := _plan.super_groups()
	var members_by_super: Array = []
	for sk in supers:
		var members: Array = []
		for k in groups.get(sk, []):
			if _cell_data.has(k):
				members.append(_cell_data[k])
		members_by_super.append(members)
	var results: Array = []
	results.resize(supers.size())
	var task := func(n: int) -> void:
		results[n] = BuildingHlod2.build(members_by_super[n], _cols, _kit, config, _plan.super_origin(supers[n]))
	if config.use_threads and supers.size() > 1:
		var group := WorkerThreadPool.add_group_task(task, supers.size(), -1, true, "building hlod2")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for n in supers.size():
			task.call(n)
	for n in supers.size():
		_install_super(supers[n], results[n] as Dictionary)


func _remove_cell(key: Vector2i) -> void:
	var node: Node = _cell_nodes.get(key)
	if node != null:
		remove_child(node)
		node.queue_free()
	_cell_nodes.erase(key)
	_cell_data.erase(key)
	_dropped.erase(key)


func _install_cell(data: BuildingCellData) -> void:
	_dropped[data.key] = data.dropped
	var old: Node = _cell_nodes.get(data.key)
	if old != null:
		remove_child(old)
		old.queue_free()
		_cell_nodes.erase(data.key)
	if data.kept.is_empty():   # hücredeki her yapı atıldı (su): düğüm yok
		_cell_data.erase(data.key)
		return
	var cell := Node3D.new()
	cell.name = "Cell_%d_%d" % [data.key.x, data.key.y]
	cell.position = Vector3(data.origin.x, 0.0, data.origin.y)
	add_child(cell)
	for n in data.modules.size():
		var m := data.modules[n]
		var count := data.counts[n]
		var casts := config.cast_shadows
		var lod1_caster := casts and config.shadow_caster_lod == 1 and _kit.has_lod1[m] == 1
		if config.build_lod0:
			var mesh0 := _kit.mesh(m, "LOD0")
			if mesh0 != null:
				var mmi0 := _make_mmi(mesh0, count)
				mmi0.multimesh.buffer = data.buffers[n]
				mmi0.name = "L0_%s" % _kit.ids[m]
				mmi0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts and not lod1_caster \
						else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				config.lod.apply(mmi0, BuildingLod.Tier.LOD0)
				cell.add_child(mmi0)
		if (config.build_lod1 or lod1_caster) and _kit.has_lod1[m] == 1:
			var mesh1 := _kit.mesh(m, "LOD1")
			if mesh1 != null:
				var mmi1 := _make_mmi(mesh1, count)
				mmi1.multimesh.buffer = data.buffers[n]
				if config.build_lod1:
					mmi1.name = "L1_%s" % _kit.ids[m]
					mmi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
							if casts and config.lod1_casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					config.lod.apply(mmi1, BuildingLod.Tier.LOD1)
					cell.add_child(mmi1)
				if lod1_caster:
					# yalnız-gölge: aynı MultiMesh (LOD1 mesh'i), LOD0 menzilinde; görsel düğüm değil
					var caster := MultiMeshInstance3D.new()
					caster.multimesh = mmi1.multimesh
					caster.material_override = _mat
					caster.name = "S1_%s" % _kit.ids[m]
					caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					config.lod.apply(caster, BuildingLod.Tier.LOD0)
					cell.add_child(caster)
				if not config.build_lod1:
					mmi1.free()   # yalnız MultiMesh kaynağı lazımdı (caster tutuyor)
	if config.build_hlod1 and data.hlod1_vertices.size() > 0:
		var mi := _make_mesh_instance(data.hlod1_vertices, data.hlod1_normals, data.hlod1_colors)
		mi.name = "HLOD1"
		config.lod.apply(mi, BuildingLod.Tier.HLOD1)
		cell.add_child(mi)
	_cell_nodes[data.key] = cell
	data.release_geometry()
	_cell_data[data.key] = data


func _install_super(skey: Vector2i, result: Dictionary) -> void:
	var old: Node = _super_nodes.get(skey)
	if old != null:
		remove_child(old)
		old.queue_free()
		_super_nodes.erase(skey)
	if result.is_empty():
		return
	var mi := _make_mesh_instance(result["vertices"], result["normals"], result["colors"])
	mi.name = "%s%d_%d" % [SUPER_PREFIX, skey.x, skey.y]
	var so := _plan.super_origin(skey)
	mi.position = Vector3(so.x, 0.0, so.y)
	config.lod.apply(mi, BuildingLod.Tier.HLOD2)
	mi.set_meta(&"boxes", int(result["boxes"]))
	add_child(mi)
	_super_nodes[skey] = mi


func _make_mmi(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat
	return mmi


func _make_mesh_instance(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) \
		-> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _proxy_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(TRIS_META, verts.size() / 3)
	return mi


func _refresh_stats() -> void:
	var kept := 0
	var dropped := 0
	var lod0 := 0
	var lod1 := 0
	for k: Vector2i in _cell_data:
		var d: BuildingCellData = _cell_data[k]
		kept += d.kept.size()
		lod0 += d.lod0_tris
		lod1 += d.lod1_tris
	var mmis := 0
	var hlod1_nodes := 0
	var hlod1_tris := 0
	for k: Vector2i in _cell_nodes:
		for child in (_cell_nodes[k] as Node3D).get_children():
			if child is MultiMeshInstance3D:
				mmis += 1
			elif child is MeshInstance3D:
				hlod1_nodes += 1
				hlod1_tris += int(child.get_meta(TRIS_META, 0))
	for k: Vector2i in _dropped:
		dropped += int(_dropped[k])
	var hlod2_tris := 0
	for k: Vector2i in _super_nodes:
		hlod2_tris += int((_super_nodes[k] as MeshInstance3D).get_meta(TRIS_META, 0))
	stats["buildings"] = _cols.count if _cols != null else 0
	stats["drawn"] = kept
	stats["dropped_water"] = dropped
	stats["cells"] = _cell_nodes.size()
	stats["supers"] = _super_nodes.size()
	stats["mmi_nodes"] = mmis
	stats["hlod1_nodes"] = hlod1_nodes
	stats["lod0_tris_all"] = lod0
	stats["lod1_tris_all"] = lod1
	stats["hlod1_tris_all"] = hlod1_tris
	stats["hlod2_tris_all"] = hlod2_tris
