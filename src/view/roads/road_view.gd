class_name RoadView
extends Node3D
## T-048: chunk başına iki birleşik mesh; mesafe LOD'u motor seçer. _process yok.
## Sim/kayıt bağı yok. Delta çağıranı eski/yeni planın etkilenen anahtar birleşimini verir.

signal chunks_rebuilt(keys: Array[Vector2i])

## Bu sayıdan az chunk yeniden kurulurken iş parçacığı kullanılmaz (yerel düzenleme yolu).
const MIN_THREADED_CHUNKS := 4

var stats: Dictionary = {}
var style: RoadStyle
## false: tüm hesap çağıran iş parçacığında (hata ayıklama / karşılaştırma). Sonuç aynıdır.
var use_threads: bool = true

var _net: WorldNetwork
var _plan: RoadChunkPlan
var _chunks: Dictionary = {}
var _material: StandardMaterial3D


func build(net: WorldNetwork, road_style: RoadStyle = null) -> void:
	clear()
	_net = net
	style = road_style if road_style != null else RoadStyle.load_default()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var started := Time.get_ticks_usec()
	_plan = RoadChunkPlan.build(net, style)
	_rebuild_with_plan(_plan.keys(), started)


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_chunks.clear()
	stats.clear()
	_net = null
	_plan = null


func plan() -> RoadChunkPlan:
	return _plan


func chunk_node(key: Vector2i) -> Node3D:
	return _chunks.get(key) as Node3D


## İndeks güncellenir; yalnız istenen chunk meshleri/düğümleri yeniden kurulur.
## Silinen/taşınan kenar için ESKİ edge_keys de çağıranın elinde kalmalıdır.
func rebuild_chunks(keys: Array[Vector2i]) -> void:
	if _net == null:
		return
	var started := Time.get_ticks_usec()
	_plan = RoadChunkPlan.build(_net, style)
	_rebuild_with_plan(keys, started)


func _rebuild_with_plan(keys: Array[Vector2i], started: int) -> void:
	var unique: Array[Vector2i] = []
	var seen: Dictionary = {}
	for key in keys:
		if not seen.has(key):
			seen[key] = true
			unique.append(key)
	var meshes := _build_chunk_data(unique)
	for key in unique:
		var old := chunk_node(key)
		if old != null:
			remove_child(old)
			old.queue_free()
		_chunks.erase(key)
		if not _plan.cells.has(key):
			continue
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
			continue
		# Aynı AABB merkezi: daha ince metro geometrisi LOD eşiklerinde boşluk açmasın.
		var bounds: AABB = (chunk.get_child(0) as MeshInstance3D).mesh.get_aabb()
		for node: MeshInstance3D in chunk.get_children():
			bounds = bounds.merge(node.mesh.get_aabb())
		for node: MeshInstance3D in chunk.get_children():
			node.custom_aabb = bounds
		add_child(chunk)
		_chunks[key] = chunk
	var near_tris := 0
	var metro_tris := 0
	for key: Vector2i in _chunks:
		for node: MeshInstance3D in (_chunks[key] as Node3D).get_children():
			if node.name == &"Near":
				near_tris += int(node.get_meta(&"tris"))
			else:
				metro_tris += int(node.get_meta(&"tris"))
	stats = {"strips": _plan.strip_count, "chunks": _chunks.size(), "near_triangles": near_tris,
		"metro_triangles": metro_tris, "last_rebuilt": unique.size(),
		"last_build_ms": (Time.get_ticks_usec() - started) / 1000.0}
	chunks_rebuilt.emit(unique)


## Chunk verisi saf fonksiyondur (ağ/plan/dünya salt okunur): çok chunk'ta WorkerThreadPool'a dağıtılır.
## Sonuç anahtar sırasından ve iş parçacığı sayısından bağımsızdır; düğümler ana iş parçacığında kurulur.
func _build_chunk_data(keys: Array[Vector2i]) -> Dictionary:
	var todo: Array[Vector2i] = []
	for key in keys:
		if _plan.cells.has(key):
			todo.append(key)
	var results: Array = []
	results.resize(todo.size())
	var job := func(index: int) -> void:
		var patch_cache: Dictionary = {}
		results[index] = [
			RoadMeshBuilder.build(_net, style, _plan, todo[index], false, patch_cache),
			RoadMeshBuilder.build(_net, style, _plan, todo[index], true, patch_cache)]
	if use_threads and todo.size() >= MIN_THREADED_CHUNKS:
		var group := WorkerThreadPool.add_group_task(job, todo.size(), -1, true, "RoadView chunks")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for index in todo.size():
			job.call(index)
	var meshes: Dictionary = {}
	for index in todo.size():
		meshes[todo[index]] = results[index]
	return meshes


func _mesh_node(data: Dictionary) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(&"tris", (data["vertices"] as PackedVector3Array).size() / 3)
	return node
