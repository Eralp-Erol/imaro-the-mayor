class_name HeroMeshLoader
extends RefCounted
## Onaylı hero bina GLB'sinden görünüm mesh'i (T-062 A3, ADR-0006 §2.4/§3.1). SAF yükleyici: hangi dosyanın
## yükleneceğini ÇAĞIRAN (BuildingKit) `LibraryGate`ten alır; bu sınıf kapı bilmez, yalnız yolu açar.
##
## Pivot normalizasyonu TEK burada: hero GLB'ler cephe çizgisinde pivotludur (+Z ön, bbox z in [-derinlik, +çıkıntı]);
## oyun tablosu `pivot_offset_m` her köşeye EKLENİR, böylece mesh'in XZ sınır kutusu merkezi origin'dedir
## (yerleşim ve `footprint_m` ayak izi merkezi varsayar). Yön (+Z cephe) ve Y (taban 0) değişmez.
## Materyal: GLB yüzey materyali (atlas) kopyalanır; Lambert + speküler kapalı (kit gölgelendiricileriyle ve hero
## lab'ıyla
## aynı ışıklandırma: sıfır parlaklık, atlas dokusundaki albedo ışıkla bir kez çarpılır).

const FLAT_SHADER_PATH := "res://assets/shaders/mat_hero_proxy.gdshader"
const VARIETY_SHADER_PATH := "res://assets/shaders/mat_hero_variety.gdshader"


## .glb sahnesi. Önce içe aktarılmış kaynak; yoksa (import koşmamış ortam) çalışma zamanında glTF okuma.
## Başarısızsa null.
static func instantiate_scene(glb_path: String) -> Node:
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed != null:
			return packed.instantiate()
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(ProjectSettings.globalize_path(glb_path), state) != OK:
		return null
	return doc.generate_scene(state)


## GLB'deki mesh'i `pivot_offset` eklenmiş (ve düğüm dönüşü uygulanmış) yeni ArrayMesh olarak döndürür; yüzey
## materyalleri atlas kopyasıdır. Dosya/mesh yoksa null (hata günlüğe yazılır).
static func load_mesh(glb_path: String, pivot_offset: Vector3, variety: BuildingVariety = null) -> ArrayMesh:
	var root := instantiate_scene(glb_path)
	if root == null:
		push_error("HeroMeshLoader: GLB açılamadı: %s" % glb_path)
		return null
	var source: MeshInstance3D = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and source == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			source = n as MeshInstance3D
		else:
			stack.append_array(n.get_children())
	if source == null:
		root.free()
		push_error("HeroMeshLoader: GLB'de mesh yok: %s" % glb_path)
		return null
	var xf := Transform3D()
	var walk: Node = source
	while walk != root and walk != null:
		xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	var out := ArrayMesh.new()
	out.resource_name = source.mesh.resource_name if not source.mesh.resource_name.is_empty() else glb_path.get_file()
	for s in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(verts.size())
		for i in verts.size():
			moved[i] = xf * verts[i] + pivot_offset
		arrays[Mesh.ARRAY_VERTEX] = moved
		if arrays[Mesh.ARRAY_NORMAL] != null and not xf.basis.is_equal_approx(Basis.IDENTITY):
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (xf.basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = null   # normal haritası yok: teğet kullanılmaz
		out.add_surface_from_arrays(source.mesh.surface_get_primitive_type(s), arrays)
		out.surface_set_material(out.get_surface_count() - 1,
				variety_material(source.mesh.surface_get_material(s), variety))
	root.free()
	return out


## Atlas materyalinin ışıklandırması: Lambert, speküler kapalı, mip'li anizotropik süzme (doku kendi atlasından).
static func shaded_material(source: Material) -> Material:
	var base := source as BaseMaterial3D
	if base == null:
		return source
	var m := base.duplicate() as BaseMaterial3D
	m.resource_name = base.resource_name
	m.roughness = 1.0
	m.metallic = 0.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## D-021: atlas dokusunu koruyan, örnek başına çatı/cephe varyantı (MultiMesh özel verisi) uygulayan malzeme.
## `variety` sabitleri (veri) uniform olur. Kaynak malzeme atlas dokusu taşımıyorsa `shaded_material` döner.
static func variety_material(source: Material, variety: BuildingVariety) -> Material:
	var base := source as BaseMaterial3D
	if base == null or base.albedo_texture == null or variety == null or not variety.enabled:
		return shaded_material(source)
	var m := ShaderMaterial.new()
	m.resource_name = base.resource_name + "_variety"
	m.shader = load(VARIETY_SHADER_PATH)
	m.set_shader_parameter("atlas", base.albedo_texture)
	m.set_shader_parameter("albedo_tint", base.albedo_color)
	m.set_shader_parameter("roof_concrete", variety.roof_concrete)
	m.set_shader_parameter("roof_zinc", variety.roof_zinc)
	m.set_shader_parameter("wall_light", variety.wall_light)
	m.set_shader_parameter("wall_light_mix", variety.wall_light_mix)
	m.set_shader_parameter("roof_line_keep", variety.roof_line_keep)
	m.set_shader_parameter("roof_shade_pivot", variety.roof_shade_pivot)
	return m


## HLOD1/HLOD2 köşe-rengi malzemesi (sRGB kodlu piştirilmiş renk).
static func flat_color_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = "mat_hero_proxy"
	mat.shader = load(FLAT_SHADER_PATH)
	return mat
