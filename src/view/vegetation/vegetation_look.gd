class_name VegetationLook
extends RefCounted
## Bitki görünüm tablosu (T-062 B1): tür dizini (`VegetationColumns.species`) -> mesh'ler (LOD0/LOD1/PROXY), leke rengi
## ve taç kabası. Tür bilgisi YALNIZ onaylı oyun tablosundan (`VegetationSpecies` / `LibraryGate`); mesh isteği her
## seferinde kapıdan yapılır, onaysız/tabloda olmayan kimlik yüklenmez (`gate.unapproved_ids` sayar).
## `numbers_only`: mesh yüklemez (saf sayısal; leke üretimi ve testler); `load_full`: ana iş parçacığında GLB + atlas
## okur.
## Leke rengi atlas dokusundan YÜKLEME ANINDA piştirilir (üçgen UV alt örnekleri, alfa maskesi uygulanır, ortalama
## doğrusal uzayda, sRGB kodlu yazılır: mat_hero_proxy sözleşmesi).

const BAKE_SUBDIVISIONS := 4
const ALPHA_CUTOFF := 0.45
const NEUTRAL := Color(0.30, 0.42, 0.20, 1.0)

var count: int = 0
var ids: PackedStringArray = PackedStringArray()
var keys: PackedStringArray = PackedStringArray()
var height_m: PackedFloat32Array = PackedFloat32Array()
var reach_m: PackedFloat32Array = PackedFloat32Array()
## 1: türün PROXY seviyesi var (palmiye).
var has_proxy: PackedByteArray = PackedByteArray()
## 1: tür leke üretir (`blob.skip_species` dışı).
var blob_on: PackedByteArray = PackedByteArray()
var crown_base_frac: PackedFloat32Array = PackedFloat32Array()
var radius_frac: PackedFloat32Array = PackedFloat32Array()
## Tür dizini -> halka listesi (Array[Vector2]).
var shape_rings: Array = []
## Leke rengi (sRGB kodlu köşe rengi).
var blob_color: PackedColorArray = PackedColorArray()
## Tür dizini -> Mesh ya da null (mesh yüklenmediyse hepsi null).
var mesh_lod0: Array = []
var mesh_lod1: Array = []
var mesh_proxy: Array = []
var gate: LibraryGate = null
var errors: PackedStringArray = PackedStringArray()


## Mesh yüklemeden: sayılar ve leke şekilleri (renk nötr yeşil).
static func numbers_only(species: VegetationSpecies, config: VegetationViewConfig) -> VegetationLook:
	var look := VegetationLook.new()
	look.gate = species.gate
	for i in species.size():
		look._add_species(species, i, config)
	return look


## Mesh'ler (kapıdan), atlas ve piştirilmiş leke renkleri. Ana iş parçacığı.
static func load_full(species: VegetationSpecies, config: VegetationViewConfig) -> VegetationLook:
	var look := numbers_only(species, config)
	var atlas_cache: Dictionary = {}
	for i in look.count:
		var rec := species.gate.request(look.ids[i])
		if rec.is_empty():
			look.errors.append("kapı reddetti: %s" % look.ids[i])
			continue
		var lods: Dictionary = rec.get("lods", {})
		look.mesh_lod0[i] = _load_level(lods, "LOD0", look.errors, look.ids[i])
		look.mesh_lod1[i] = _load_level(lods, "LOD1", look.errors, look.ids[i])
		if look.has_proxy[i] == 1:
			look.mesh_proxy[i] = _load_level(lods, "PROXY", look.errors, look.ids[i])
		var atlas := _atlas_image(rec, atlas_cache)
		var source: Mesh = look.mesh_lod1[i] if look.mesh_lod1[i] != null else look.mesh_lod0[i]
		if source is ArrayMesh and atlas != null:
			look.blob_color[i] = bake_color(source as ArrayMesh, atlas)
		else:
			look.errors.append("leke rengi piştirilemedi (atlas/mesh yok): %s" % look.ids[i])
	return look


## Kapıdan mesh: kimlik kapıdan geçmezse null (ret sayılır ve izlenir), GLB açılmaz.
static func mesh_for(the_gate: LibraryGate, id: String, level: String) -> Mesh:
	var rec := the_gate.request(id)
	if rec.is_empty():
		return null
	var errs := PackedStringArray()
	return _load_level(rec.get("lods", {}) as Dictionary, level, errs, id)


## Mesh -> alan ağırlıksız, alfa maskeli ortalama renk (doğrusal ortalama, sRGB kodlu çıktı).
static func bake_color(mesh: ArrayMesh, atlas: Image) -> Color:
	var acc := Vector3.ZERO
	var weight := 0.0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if uvs.size() != verts.size():
			continue
		var idx: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		else:
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		for t in range(0, idx.size() - 2, 3):
			var area := 0.5 * (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]]).length()
			var sample := _triangle_sample(atlas, uvs[idx[t]], uvs[idx[t + 1]], uvs[idx[t + 2]])
			if sample.w > 0.0:
				acc += Vector3(sample.x, sample.y, sample.z) * area * sample.w
				weight += area * sample.w
	if weight <= 0.0:
		return NEUTRAL
	var m := acc / weight
	return Color(m.x, m.y, m.z, 1.0).linear_to_srgb()


func index_of_key(key: String) -> int:
	return keys.find(key)


func _add_species(species: VegetationSpecies, i: int, config: VegetationViewConfig) -> void:
	var key := species.keys[i]
	var spec_look := config.look_of(key)
	if spec_look.is_empty():
		errors.append("species_look yok: %s" % key)
	count += 1
	ids.append(species.ids[i])
	keys.append(key)
	height_m.append(species.height_m[i])
	reach_m.append(species.reach_m[i])
	has_proxy.append(1 if species.has_proxy(i) else 0)
	blob_on.append(0 if config.blob_skip_species.has(key) or spec_look.is_empty() else 1)
	crown_base_frac.append(float(spec_look.get("crown_base_frac", 0.3)))
	radius_frac.append(float(spec_look.get("radius_frac", 0.9)))
	shape_rings.append(config.blob_shapes.get(str(spec_look.get("shape", "")), []))
	blob_color.append(NEUTRAL)
	mesh_lod0.append(null)
	mesh_lod1.append(null)
	mesh_proxy.append(null)


static func _load_level(lods: Dictionary, level: String, errs: PackedStringArray, id: String) -> Mesh:
	if not lods.has(level):
		errs.append("%s: %s seviyesi yok" % [id, level])
		return null
	var mesh := HeroMeshLoader.load_mesh(str((lods[level] as Dictionary).get("glb", "")), Vector3.ZERO)
	if mesh == null:
		errs.append("%s: %s GLB yüklenemedi" % [id, level])
	return mesh


static func _atlas_image(rec: Dictionary, cache: Dictionary) -> Image:
	var atlas: Variant = rec.get("atlas")
	if not (atlas is Dictionary):
		return null
	var path := str((atlas as Dictionary).get("path", ""))
	if path.is_empty():
		return null
	if cache.has(path):
		return cache[path]
	var tex := load(path) as Texture2D
	var img: Image = null
	if tex != null:
		img = tex.get_image()
		if img != null and img.is_compressed():
			img.decompress()
	cache[path] = img
	return img


## Üçgen UV alanı N x N alt üçgene bölünür; alfa maskesinden geçen örneklerin DOĞRUSAL ortalaması + geçen oran
## (w). Dönüş (r, g, b, w): w = 0 hiç örnek geçmedi.
static func _triangle_sample(atlas: Image, a: Vector2, b: Vector2, c: Vector2) -> Vector4:
	var n := BAKE_SUBDIVISIONS
	var acc := Vector3.ZERO
	var kept := 0
	var total := 0
	var w := atlas.get_width()
	var h := atlas.get_height()
	for i in n:
		for j in n - i:
			var up_uv := _sub_center(a, b, c, [Vector2(i, j), Vector2(i + 1, j), Vector2(i, j + 1)], n)
			var s_up := _sample_px(atlas, w, h, up_uv)
			total += 1
			if s_up.w > 0.0:
				kept += 1
				acc += Vector3(s_up.x, s_up.y, s_up.z)
			if i + j < n - 1:
				var down_uv := _sub_center(a, b, c, [Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)], n)
				var s_dn := _sample_px(atlas, w, h, down_uv)
				total += 1
				if s_dn.w > 0.0:
					kept += 1
					acc += Vector3(s_dn.x, s_dn.y, s_dn.z)
	if kept == 0:
		return Vector4.ZERO
	var m := acc / float(kept)
	return Vector4(m.x, m.y, m.z, float(kept) / float(total))


## Atlas pikseli (doğrusal rgb, w = 1 alfa geçti / 0 geçmedi).
static func _sample_px(atlas: Image, w: int, h: int, uv: Vector2) -> Vector4:
	var px := clampi(int(floor(fposmod(uv.x, 1.0) * float(w))), 0, w - 1)
	var py := clampi(int(floor(fposmod(uv.y, 1.0) * float(h))), 0, h - 1)
	var col := atlas.get_pixel(px, py)
	if col.a < ALPHA_CUTOFF:
		return Vector4.ZERO
	var lin := col.srgb_to_linear()
	return Vector4(lin.r, lin.g, lin.b, 1.0)


static func _sub_center(a: Vector2, b: Vector2, c: Vector2, corners: Array, n: int) -> Vector2:
	var u := Vector2.ZERO
	var fn := float(n)
	for p: Vector2 in corners:
		u += a * (1.0 - p.x / fn - p.y / fn) + b * (p.x / fn) + c * (p.y / fn)
	return u / 3.0
