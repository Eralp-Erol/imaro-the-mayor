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
@export var shading_exaggeration: float = 3.0
@export var use_threads: bool = true
## Kara chunk'ları gölge düşürür (su düşürmez; ikisi de alır). Gölgeyi açan ışık sahnededir; burada yalnız katılım.
@export var cast_shadows: bool = true
## true: kara + su için ayrıca TEK birleşik "uzak" mesh kurulur (FarLod; metro uzaklığında chunk'lar yerine çizilir:
## ~150 draw call -> 2). Aynı köşeler ve malzemeler (yalnız temsil); bellek ~bir kopya daha. Varsayılan kapalı.
@export var build_far_mesh: bool = false

## Son kurulumun ölçümleri: data_ms (mesh verisi), mesh_ms (ArrayMesh+düğüm), chunk/üçgen sayıları.
var stats: Dictionary = {}

var _world: WorldData
var _palette: TerrainPalette
var _material: ShaderMaterial
var _water_material: StandardMaterial3D
var _look: TerrainLook
var _land_nodes: Array[MeshInstance3D] = []
var _water_nodes: Array[MeshInstance3D] = []
var _chunk_counts: Vector2i = Vector2i.ZERO
var _land_data: Array = []
var _water_data: Array = []
var _far_nodes: Array[MeshInstance3D] = []
var _far_mode: bool = false


## Eski çocukları siler, WorldData'dan tüm chunk'ları kurar.
func build(world: WorldData) -> void:
	clear()
	_world = world
	var t_pal := Time.get_ticks_usec()
	_palette = TerrainPalette.new(world)
	var palette_ms := snappedf((Time.get_ticks_usec() - t_pal) / 1000.0, 0.1)
	_look = TerrainLook.shared()
	_material = _look.make_material()
	_water_material = _make_water_material()
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
			var node := _make_node(land, false, origin, "Land_%d_%d" % [cx, cz], _material)
			_land_nodes.append(node)
			land_tris += int(land["triangles"])
			land_verts += (land["vertices"] as PackedVector3Array).size()
		var water: Dictionary = _water_data[k]
		if int(water["triangles"]) > 0:
			_water_nodes.append(_make_node(water, true, origin, "Water_%d_%d" % [cx, cz], _water_material))
			water_tris += int(water["triangles"])
	var t_far := Time.get_ticks_usec()
	if build_far_mesh:
		_build_far(world)
	var far_ms := snappedf((Time.get_ticks_usec() - t_far) / 1000.0, 0.1)
	_land_data.clear()
	_water_data.clear()
	var t2 := Time.get_ticks_usec()
	stats = {
		"chunk_cells": chunk_cells, "chunk_size_m": chunk_cells * world.cell_size, "lod_stride": lod_stride,
		"chunks_x": _chunk_counts.x, "chunks_z": _chunk_counts.y,
		"land_chunks": _land_nodes.size(), "water_chunks": _water_nodes.size(),
		"land_triangles": land_tris, "water_triangles": water_tris, "land_vertices": land_verts,
		"palette_ms": palette_ms, "data_ms": snappedf((t1 - t0) / 1000.0, 0.1), "mesh_ms": snappedf((t2 - t1) / 1000.0, 0.1),
		"threaded": use_threads, "far_nodes": _far_nodes.size(), "far_ms": far_ms,
		"ground": _ground_stats(),
	}


## Kent zemini (T-051): yapılı parsel maskesini bir kez hesaplar ve ortak arazi malzemesine verir (chunk'lar ve
## uzak mesh aynı malzemeyi paylaşır: yeni draw call/malzeme yok). Yapılar kurulduktan SONRA çağrılır.
## Dönüş: maske istatistikleri (boşsa {}). Maske yoksa/veri yoksa arazi eskisi gibi kalır.
func apply_urban_ground(net: WorldNetwork, cols: BuildingColumns) -> Dictionary:
	if _material == null or _look == null:
		return {}
	var mask := UrbanGroundMask.build(net, cols, _look.urban_mask_params())
	if mask.is_empty():
		return {}
	var image: Image = mask["image"]
	image.generate_mipmaps()
	var tex := ImageTexture.create_from_image(image)
	var origin: Vector2 = mask["origin"]
	var size: Vector2 = mask["size"]
	_material.set_shader_parameter("urban_tex", tex)
	_material.set_shader_parameter("urban_rect", Vector4(origin.x, origin.y, size.x, size.y))
	stats["urban_mask"] = {"px": image.get_size(), "cell_m": mask["cell_m"], "parcels": mask["parcels"], "ms": mask["ms"]}
	return stats["urban_mask"]


## Ortak arazi malzemesi (testler/ölçüm).
func material() -> ShaderMaterial:
	return _material


## T-062 A4: zemin katmanı kümesi ölçümleri (onaylı katman sayısı, boyut, kapı ret sayacı, kurulum hataları).
func _ground_stats() -> Dictionary:
	var layers := GroundLayerSet.shared()
	return {"layers": layers.count(), "size_px": layers.size_px, "mips": layers.mip_levels,
		"errors": layers.errors.size(), "unapproved_ids": layers.gate.unapproved_ids.size(),
		"array_ok": layers.array != null}


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_land_nodes.clear()
	_water_nodes.clear()
	_far_nodes.clear()
	_far_mode = false


## Uzak mod (FarLod): true iken chunk'lı kara/su gizlenir, birleşik uzak meshler çizilir. Uzak mesh yoksa etkisiz.
func set_far_mode(far: bool) -> void:
	if far == _far_mode or _far_nodes.is_empty():
		return
	_far_mode = far
	for node in _land_nodes:
		node.visible = not far
	for node in _water_nodes:
		node.visible = not far
	for node in _far_nodes:
		node.visible = far


func far_mode() -> bool:
	return _far_mode


func far_nodes() -> Array[MeshInstance3D]:
	return _far_nodes


func chunk_counts() -> Vector2i:
	return _chunk_counts


func land_nodes() -> Array[MeshInstance3D]:
	return _land_nodes


func water_nodes() -> Array[MeshInstance3D]:
	return _water_nodes


## Dünya konumundaki (x, z) kara/su yüksekliği: görünümün kullandığı veri (kamera çarpışması vb.).
func surface_height_at(x: float, z: float) -> float:
	return maxf(_world.height_at(x, z), _world.sea_level) if _world != null else 0.0


## Tüm chunk verisini tek kara + tek su meshinde birleştirir (köşe = chunk yerel + chunk başlangıcı; düğüm dünya
## başlangıcında). Başlangıçta gizli; `set_far_mode(true)` gösterir.
func _build_far(world: WorldData) -> void:
	for water in [false, true]:
		var parts: Array = []
		var offsets: Array = []
		for k in _land_data.size():
			var d: Dictionary = (_water_data[k] if water else _land_data[k])
			if int(d["triangles"]) <= 0:
				continue
			parts.append(d)
			offsets.append(TerrainMeshBuilder.chunk_origin(world, k % _chunk_counts.x, k / _chunk_counts.x, chunk_cells))
		if parts.is_empty():
			continue
		var merged := FarLod.merge_parts(parts, offsets)
		var node := _make_node(merged, water, Vector3.ZERO, "FarWater" if water else "FarLand",
				_water_material if water else _material)
		node.visible = false
		_far_nodes.append(node)


func _build_chunk_data(k: int) -> void:
	var cx := k % _chunk_counts.x
	var cz := k / _chunk_counts.x
	_land_data[k] = TerrainMeshBuilder.build_land(_world, _palette, cx, cz, chunk_cells, lod_stride, skirts,
			shading_exaggeration, _look)
	_water_data[k] = TerrainMeshBuilder.build_water(_world, _palette, cx, cz, chunk_cells)


func _make_node(data: Dictionary, indexed: bool, origin: Vector3, node_name: String,
		material: Material) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = data["normals"]
	arrays[Mesh.ARRAY_COLOR] = data["colors"]
	if data.has("uvs"):
		arrays[Mesh.ARRAY_TEX_UV] = data["uvs"]
	if data.has("uv2s"):
		arrays[Mesh.ARRAY_TEX_UV2] = data["uv2s"]
	if indexed:
		arrays[Mesh.ARRAY_INDEX] = data["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.position = origin
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows and not indexed \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _make_water_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m
