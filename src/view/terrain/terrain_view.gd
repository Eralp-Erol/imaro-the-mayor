class_name TerrainView
extends Node3D
## WorldData'dan chunk'lı arazi + su görünümü (T-001 ölçüt 4; ADR-0002 görünüm katmanı). Yalnız WorldData OKUR;
## simülasyon verisine yazmaz. Ayrı harita resmi yok: yükseklik, renk ve su aynı örneklerden türer (WLD-01, TEK-03).
##
## Chunk mesh VERİSİ (TerrainMeshBuilder) iş parçacıklarında hesaplanır; ArrayMesh/MeshInstance3D kurulumu ana
## iş parçacığındadır. Chunk başına en çok iki MeshInstance3D (kara + su) = en çok iki draw call; tek paylaşılan
## materyal.

## Chunk kenarı (hücre). 40 hücre x 100 m = 4 km: 4x4 adet 1 km bina chunk'ına (ADR-0001) hizalanır.
@export var chunk_cells: int = 40
## 1 = tam çözünürlük; 2, 4 … = kaba örnekleme (ölçüm/LOD deneyi; dikiş çatlağı önlemi YOK, bkz. rapor).
@export var lod_stride: int = 1
@export var skirts: bool = true
## Yalnız GÖLGELEME eğimini büyütür (hillshade z-faktörü); geometri ve yükseklikler gerçektir. 1 = gerçek eğim.
@export var shading_exaggeration: float = 4.0
@export var use_threads: bool = true

## Son kurulumun ölçümleri: data_ms (mesh verisi), mesh_ms (ArrayMesh+düğüm), chunk/üçgen sayıları.
var stats: Dictionary = {}

var _world: WorldData
var _palette: TerrainPalette
var _material: StandardMaterial3D
var _land_nodes: Array[MeshInstance3D] = []
var _water_nodes: Array[MeshInstance3D] = []
var _chunk_counts: Vector2i = Vector2i.ZERO
var _land_data: Array = []
var _water_data: Array = []


## Eski çocukları siler, WorldData'dan tüm chunk'ları kurar.
func build(world: WorldData) -> void:
	clear()
	_world = world
	var t_pal := Time.get_ticks_usec()
	_palette = TerrainPalette.new(world)
	var palette_ms := snappedf((Time.get_ticks_usec() - t_pal) / 1000.0, 0.1)
	_material = _make_material()
	_chunk_counts = TerrainMeshBuilder.chunk_counts(world, chunk_cells)
	var count := _chunk_counts.x * _chunk_counts.y
	_land_data.resize(count)
	_water_data.resize(count)

	var t0 := Time.get_ticks_usec()
	if use_threads and count > 1:
		var group := WorkerThreadPool.add_group_task(_build_chunk_data, count, -1, true, "terrain chunks")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for k in count:
			_build_chunk_data(k)
	var t1 := Time.get_ticks_usec()

	var land_tris := 0
	var water_tris := 0
	var land_verts := 0
	for k in count:
		var cx := k % _chunk_counts.x
		var cz := k / _chunk_counts.x
		var origin := TerrainMeshBuilder.chunk_origin(world, cx, cz, chunk_cells)
		var land: Dictionary = _land_data[k]
		if int(land["triangles"]) > 0:
			var node := _make_node(land, false, origin, "Land_%d_%d" % [cx, cz])
			_land_nodes.append(node)
			land_tris += int(land["triangles"])
			land_verts += (land["vertices"] as PackedVector3Array).size()
		var water: Dictionary = _water_data[k]
		if int(water["triangles"]) > 0:
			_water_nodes.append(_make_node(water, true, origin, "Water_%d_%d" % [cx, cz]))
			water_tris += int(water["triangles"])
	_land_data.clear()
	_water_data.clear()
	var t2 := Time.get_ticks_usec()
	stats = {
		"chunk_cells": chunk_cells, "chunk_size_m": chunk_cells * world.cell_size, "lod_stride": lod_stride,
		"chunks_x": _chunk_counts.x, "chunks_z": _chunk_counts.y,
		"land_chunks": _land_nodes.size(), "water_chunks": _water_nodes.size(),
		"land_triangles": land_tris, "water_triangles": water_tris, "land_vertices": land_verts,
		"palette_ms": palette_ms, "data_ms": snappedf((t1 - t0) / 1000.0, 0.1), "mesh_ms": snappedf((t2 - t1) / 1000.0, 0.1),
		"threaded": use_threads,
	}


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_land_nodes.clear()
	_water_nodes.clear()


func chunk_counts() -> Vector2i:
	return _chunk_counts


func land_nodes() -> Array[MeshInstance3D]:
	return _land_nodes


func water_nodes() -> Array[MeshInstance3D]:
	return _water_nodes


## Dünya konumundaki (x, z) kara/su yüksekliği: görünümün kullandığı veri (kamera çarpışması vb.).
func surface_height_at(x: float, z: float) -> float:
	return maxf(_world.height_at(x, z), _world.sea_level) if _world != null else 0.0


func _build_chunk_data(k: int) -> void:
	var cx := k % _chunk_counts.x
	var cz := k / _chunk_counts.x
	_land_data[k] = TerrainMeshBuilder.build_land(_world, _palette, cx, cz, chunk_cells, lod_stride, skirts,
			shading_exaggeration)
	_water_data[k] = TerrainMeshBuilder.build_water(_world, cx, cz, chunk_cells)


func _make_node(data: Dictionary, indexed: bool, origin: Vector3, node_name: String) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = origin
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _make_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m
