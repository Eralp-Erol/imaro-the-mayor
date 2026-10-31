class_name RoadView
extends Node3D
## T-048: chunk başına iki birleşik mesh; mesafe LOD'u motor seçer. _process yok.
## Sim/kayıt bağı yok. Delta çağıranı eski/yeni planın etkilenen anahtar birleşimini verir.

signal chunks_rebuilt(keys: Array[Vector2i])

## Bu sayıdan az chunk yeniden kurulurken iş parçacığı kullanılmaz (yerel düzenleme yolu).
const MIN_THREADED_CHUNKS := 4
## Kare dilimi (yol onayı sonrası kurulum): `step_install`/`step_far` bir çağrıda en az bir iş yapar, süre bu bütçeyi
## aşınca durur. Ölçüm (Intel Mac, başsız, yük altında): bir 2 km'lik chunk'ın iki ArrayMesh'i ~2-3 ms.
const INSTALL_BUDGET_US := 4000
## Uzak (FarLod) mesh dilimli kurulurken tek yüzeyin en çok köşesi: ArrayMesh yüzey kurulumu bölünemez (236k köşe tek
## yüzeyde ~28 ms ölçüldü), bu yüzden uzak mesh bu boyda yüzeylere bölünür (bir yüzey = bir kare işi). Köşeler/sıra
## tek yüzeyli sürümle AYNI; yalnız yüzey sınırları ve uzak moddaki draw call sayısı (1 -> ~10) farklıdır.
const FAR_GROUP_VERTS := 24000
const SHADER_PATH := "res://art/shaders/road_surface.gdshader"

var stats: Dictionary = {}
var style: RoadStyle
## false: tüm hesap çağıran iş parçacığında (hata ayıklama / karşılaştırma). Sonuç aynıdır.
var use_threads: bool = true
## true: tüm chunk'ların METRO meshleri ayrıca TEK birleşik "uzak" mesh olarak kurulur (FarLod). `set_far_mode(true)`
## chunk düğümlerini gizleyip bunu gösterir: ~260 draw call -> 1 (Compatibility'de draw call başına ~15-20 us).
## Aynı köşeler (metro temsili); CPU'da metro köşe dizileri tutulur (~10 MB). Varsayılan kapalı.
var build_far_mesh: bool = false
## Dilimli uzak mesh yüzey boyu (testler küçültür; varsayılan `FAR_GROUP_VERTS`).
var far_group_verts: int = FAR_GROUP_VERTS

var _net: WorldNetwork
var _plan: RoadChunkPlan
var _chunks: Dictionary = {}
var _material: ShaderMaterial
var _layers: GroundLayerSet
var _far_parts: Dictionary = {}
var _far_node: MeshInstance3D = null
var _far_mode: bool = false
## Dilimli kurulum (bkz. `begin_install`): {keys, meshes, index, started}; boşsa iş yok.
var _stage: Dictionary = {}
## Dilimli uzak mesh işi: {groups: Array[Array], index, mesh: ArrayMesh, tris}; boşsa iş yok.
var _far_job: Dictionary = {}
var _far_dirty: bool = false


func build(net: WorldNetwork, road_style: RoadStyle = null) -> void:
	clear()
	_net = net
	style = road_style if road_style != null else RoadStyle.load_default()
	# T-062 A4: yüzey onaylı zemin katmanlarından (ana iş parçacığında bir kez çözülür; mesh iş parçacıkları yalnız okur).
	_layers = GroundLayerSet.shared()
	style.bind_layers(_layers)
	_material = _make_material(_layers, style)
	var started := Time.get_ticks_usec()
	_plan = RoadChunkPlan.build(net, style)
	_rebuild_with_plan(_plan.keys(), started)


## Ortak yol malzemesi (testler/ölçüm).
func material() -> ShaderMaterial:
	return _material


func _make_material(layers: GroundLayerSet, road_style: RoadStyle) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	if layers.array != null:
		m.set_shader_parameter("layers", layers.array)
	var tiles := PackedFloat32Array()
	tiles.resize(TerrainLook.MAX_LAYERS)
	for i in mini(layers.count(), TerrainLook.MAX_LAYERS):
		tiles[i] = layers.tile_m[i]
	m.set_shader_parameter("tile_m", tiles)
	m.set_shader_parameter("walk_layer", float(road_style.walk_layer()))
	var surface: Dictionary = road_style.data["surface"]
	m.set_shader_parameter("curb_m", float(surface["curb_m"]))
	m.set_shader_parameter("curb_dark", float(surface["curb_dark"]))
	m.set_shader_parameter("detail_far", float(surface["detail_far_m"]))
	var fade: Array = surface["fade_to_mean_m"]
	m.set_shader_parameter("fade_to_mean", Vector2(float(fade[0]), float(fade[1])))
	# Hava tonu arazi ile AYNI veriden (uzak yollar araziden kopmasın).
	var haze: Dictionary = TerrainLook.shared().data["haze"]
	var hc: Array = haze["color"]
	m.set_shader_parameter("haze_color", Color(float(hc[0]), float(hc[1]), float(hc[2])))
	m.set_shader_parameter("haze_range", Vector2(float(haze["start_m"]), float(haze["end_m"])))
	m.set_shader_parameter("haze_amount", float(haze["amount"]))
	return m


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_chunks.clear()
	_far_parts.clear()
	_far_node = null
	_far_mode = false
	_stage = {}
	_far_job = {}
	_far_dirty = false
	stats.clear()
	_net = null
	_plan = null


## Uzak mod (FarLod): chunk düğümleri gizlenir, birleşik uzak yol meshi gösterilir. Uzak mesh yoksa etkisiz.
func set_far_mode(far: bool) -> void:
	if far == _far_mode or _far_node == null:
		return
	_far_mode = far
	for key: Vector2i in _chunks:
		(_chunks[key] as Node3D).visible = not far
	_far_node.visible = far


func far_mode() -> bool:
	return _far_mode


func far_node() -> MeshInstance3D:
	return _far_node


func _refresh_far_mesh() -> void:
	_far_job = {}
	_far_dirty = false
	if _far_node != null:
		remove_child(_far_node)
		_far_node.queue_free()
		_far_node = null
	if _far_parts.is_empty():
		return
	var keys: Array = _far_parts.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var parts: Array = []
	var offsets: Array = []
	for key: Vector2i in keys:
		parts.append(_far_parts[key]["data"])
		offsets.append(_far_parts[key]["offset"])
	_far_node = _mesh_node(FarLod.merge_parts(parts, offsets))
	_far_node.name = "FarRoads"
	_far_node.visible = _far_mode
	add_child(_far_node)


func plan() -> RoadChunkPlan:
	return _plan


func chunk_node(key: Vector2i) -> Node3D:
	return _chunks.get(key) as Node3D


## İndeks güncellenir; yalnız istenen chunk meshleri/düğümleri yeniden kurulur.
## Silinen/taşınan kenar için ESKİ edge_keys de çağıranın elinde kalmalıdır. `new_plan`: çağıran yeni planı zaten
## çıkardıysa (anahtar birleşimi için) verir; ikinci kez O(ağ) indeks kurulmaz (`RoadEditSync`).
func rebuild_chunks(keys: Array[Vector2i], new_plan: RoadChunkPlan = null) -> void:
	if _net == null:
		return
	var started := Time.get_ticks_usec()
	_plan = new_plan if new_plan != null else RoadChunkPlan.build(_net, style)
	_rebuild_with_plan(keys, started)


func _rebuild_with_plan(keys: Array[Vector2i], started: int) -> void:
	var unique := _unique_keys(keys)
	_install_chunks(unique, _build_chunk_data(unique, _plan, use_threads), started)


## T-042 adım 3 · İKİ AŞAMALI kurulum (kare sıçramasını ana iş parçacığından almak için): `compute_chunk_data` SAF ve
## iş parçacığı güvenlidir (ağ/plan salt okunur; çağıran ağın değişmediğini sağlar), `install_chunks` düğümleri ANA
## iş parçacığında kurar. `rebuild_chunks` = ikisi art arda. `new_plan` verilmişse önce indekse alınır.
func compute_chunk_data(keys: Array[Vector2i], plan_in: RoadChunkPlan) -> Dictionary:
	return _build_chunk_data(_unique_keys(keys), plan_in, false)


func install_chunks(keys: Array[Vector2i], plan_in: RoadChunkPlan, meshes: Dictionary, started: int = -1) -> void:
	if _net == null:
		return
	_plan = plan_in
	_install_chunks(_unique_keys(keys), meshes, started if started >= 0 else Time.get_ticks_usec())


func _unique_keys(keys: Array[Vector2i]) -> Array[Vector2i]:
	var unique: Array[Vector2i] = []
	var seen: Dictionary = {}
	for key in keys:
		if not seen.has(key):
			seen[key] = true
			unique.append(key)
	return unique


func _install_chunks(unique: Array[Vector2i], meshes: Dictionary, started: int) -> void:
	_stage = {}
	for key in unique:
		_install_one(key, meshes)
	if build_far_mesh:
		_refresh_far_mesh()
	_finish_install(unique, started)


## Tek chunk'ın düğümlerini kurar (eskisini söker). Senkron ve dilimli kurulumun ortak gövdesi.
func _install_one(key: Vector2i, meshes: Dictionary) -> void:
	var old := chunk_node(key)
	if old != null:
		remove_child(old)
		old.queue_free()
	_chunks.erase(key)
	_far_parts.erase(key)
	if not _plan.cells.has(key):
		return
	var chunk := Node3D.new()
	chunk.name = "Road_%d_%d" % [key.x, key.y]
	var origin := _plan.rect(key).position
	chunk.position = Vector3(origin.x, 0.0, origin.y)
	for metro in [false, true]:
		var data: Dictionary = (meshes[key] as Array)[1 if metro else 0]
		if (data["vertices"] as PackedVector3Array).is_empty():
			continue
		var node := _mesh_node(data)
		node.name = "Metro" if metro else "Near"
		if metro:
			node.visibility_range_begin = float(style.data["metro_begin_m"])
		else:
			node.visibility_range_end = float(style.data["metro_begin_m"])
		chunk.add_child(node)
	if chunk.get_child_count() == 0:
		chunk.free()
		return
	# Aynı AABB merkezi: daha ince metro geometrisi LOD eşiklerinde boşluk açmasın.
	var bounds: AABB = (chunk.get_child(0) as MeshInstance3D).mesh.get_aabb()
	for node: MeshInstance3D in chunk.get_children():
		bounds = bounds.merge(node.mesh.get_aabb())
	for node: MeshInstance3D in chunk.get_children():
		node.custom_aabb = bounds
	chunk.visible = not _far_mode
	add_child(chunk)
	_chunks[key] = chunk
	if build_far_mesh:
		var metro_data: Dictionary = (meshes[key] as Array)[1]
		if not (metro_data["vertices"] as PackedVector3Array).is_empty():
			_far_parts[key] = {"data": metro_data, "offset": chunk.position}


func _finish_install(unique: Array[Vector2i], started: int) -> void:
	var near_tris := 0
	var metro_tris := 0
	for key: Vector2i in _chunks:
		for node: MeshInstance3D in (_chunks[key] as Node3D).get_children():
			if node.name == &"Near":
				near_tris += int(node.get_meta(&"tris"))
			else:
				metro_tris += int(node.get_meta(&"tris"))
	var far_tris := 0
	if _far_node != null:
		far_tris = int(_far_node.get_meta(&"tris"))
	stats = {"far_triangles": far_tris, "strips": _plan.strip_count, "chunks": _chunks.size(), "near_triangles": near_tris,
		"metro_triangles": metro_tris, "last_rebuilt": unique.size(),
		"last_build_ms": (Time.get_ticks_usec() - started) / 1000.0}
	chunks_rebuilt.emit(unique)


## KARE DİLİMLİ kurulum (yol onayı sonrası ana iş parçacığı sıçramasını önlemek için): `begin_install` planı alır ve işi
## sıraya koyar, `step_install` her çağrıda bütçe dolana kadar chunk kurar (en az bir). Kurulan chunk'lar
## eskisinin yerine
## geçer; henüz sırası gelmeyenler birkaç kare eski görünümde kalır. Biten iş `install_chunks` ile AYNI
## düğümleri/istatistiği
## üretir. Uzak mesh (`build_far_mesh`) ayrıca `step_far` ile dilimli yenilenir.
func begin_install(keys: Array[Vector2i], plan_in: RoadChunkPlan, meshes: Dictionary, started: int = -1) -> void:
	if _net == null:
		return
	_plan = plan_in
	_stage = {"keys": _unique_keys(keys), "meshes": meshes, "index": 0,
			"started": started if started >= 0 else Time.get_ticks_usec()}


func install_pending() -> bool:
	return not _stage.is_empty()


## true = kurulum bitti (ya da iş yoktu).
func step_install(budget_us: int = INSTALL_BUDGET_US) -> bool:
	if _stage.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	var keys: Array[Vector2i] = _stage["keys"]
	var first: int = _stage["index"]
	var i := first
	while i < keys.size():
		if i > first and Time.get_ticks_usec() - t0 >= budget_us:
			break
		_install_one(keys[i], _stage["meshes"])
		i += 1
	_stage["index"] = i
	if i < keys.size():
		return false
	var done := _stage
	_stage = {}
	if build_far_mesh:
		_far_dirty = true
		_far_job = {}
	_finish_install(keys, int(done["started"]))
	return true


## Uzak mesh yenilemesi bekliyor mu?
func far_pending() -> bool:
	return build_far_mesh and (_far_dirty or not _far_job.is_empty())


## Uzak meshi dilimli yeniler (`_refresh_far_mesh` ile aynı köşeler, FAR_GROUP_VERTS'lik yüzeyler). true = iş kalmadı.
func step_far(budget_us: int = INSTALL_BUDGET_US) -> bool:
	if not build_far_mesh:
		_far_dirty = false
		_far_job = {}
		return true
	if _far_job.is_empty():
		if not _far_dirty:
			return true
		_far_dirty = false
		_far_job = _begin_far_job()
		if _far_job.is_empty():
			_swap_far_node(null)
			return true
	var t0 := Time.get_ticks_usec()
	var groups: Array = _far_job["groups"]
	var first: int = _far_job["index"]
	var i := first
	while i < groups.size():
		if i > first and Time.get_ticks_usec() - t0 >= budget_us:
			break
		var group: Dictionary = groups[i]
		var data := FarLod.merge_parts(group["parts"], group["offsets"])
		(_far_job["mesh"] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(data))
		_far_job["tris"] = int(_far_job["tris"]) + (data["vertices"] as PackedVector3Array).size() / 3
		i += 1
	_far_job["index"] = i
	if i < groups.size():
		return false
	var node := _mesh_instance(_far_job["mesh"] as ArrayMesh, int(_far_job["tris"]))
	_far_job = {}
	_swap_far_node(node)
	return not _far_dirty


## Bekleyen uzak mesh işini TAMAMEN yürütür (testler/kapanış).
func settle_far() -> void:
	while not step_far(1 << 40):
		pass


func _begin_far_job() -> Dictionary:
	var keys: Array = _far_parts.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var groups: Array = []
	var parts: Array = []
	var offsets: Array = []
	var verts := 0
	for key: Vector2i in keys:
		var data: Dictionary = _far_parts[key]["data"]
		parts.append(data)
		offsets.append(_far_parts[key]["offset"])
		verts += (data["vertices"] as PackedVector3Array).size()
		if verts >= far_group_verts:
			groups.append({"parts": parts, "offsets": offsets})
			parts = []
			offsets = []
			verts = 0
	if not parts.is_empty():
		groups.append({"parts": parts, "offsets": offsets})
	if groups.is_empty():
		return {}
	return {"groups": groups, "index": 0, "mesh": ArrayMesh.new(), "tris": 0}


func _swap_far_node(node: MeshInstance3D) -> void:
	if _far_node != null:
		remove_child(_far_node)
		_far_node.queue_free()
		_far_node = null
	if node != null:
		node.name = "FarRoads"
		node.visible = _far_mode
		add_child(node)
		_far_node = node
	stats["far_triangles"] = 0 if node == null else int(node.get_meta(&"tris"))


## Chunk verisi saf fonksiyondur (ağ/plan/dünya salt okunur): çok chunk'ta WorkerThreadPool'a dağıtılır.
## Sonuç anahtar sırasından ve iş parçacığı sayısından bağımsızdır; düğümler ana iş parçacığında kurulur.
func _build_chunk_data(keys: Array[Vector2i], plan_in: RoadChunkPlan, threaded: bool) -> Dictionary:
	var todo: Array[Vector2i] = []
	for key in keys:
		if plan_in.cells.has(key):
			todo.append(key)
	var results: Array = []
	results.resize(todo.size())
	var job := func(index: int) -> void:
		var patch_cache: Dictionary = {}
		results[index] = [
			RoadMeshBuilder.build(_net, style, plan_in, todo[index], false, patch_cache),
			RoadMeshBuilder.build(_net, style, plan_in, todo[index], true, patch_cache)]
	if threaded and todo.size() >= MIN_THREADED_CHUNKS:
		var group := WorkerThreadPool.add_group_task(job, todo.size(), -1, true, "RoadView chunks")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for index in todo.size():
			job.call(index)
	var meshes: Dictionary = {}
	for index in todo.size():
		meshes[todo[index]] = results[index]
	return meshes


func _surface_arrays(data: Dictionary) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	if data.has("uvs"):
		arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	return arrays


func _mesh_node(data: Dictionary) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays(data))
	return _mesh_instance(mesh, (data["vertices"] as PackedVector3Array).size() / 3)


func _mesh_instance(mesh: ArrayMesh, tris: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(&"tris", tris)
	return node
