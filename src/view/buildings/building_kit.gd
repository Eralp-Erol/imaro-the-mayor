class_name BuildingKit
extends RefCounted
## Render için bina tablosu (T-012; T-062 A3, ADR-0006 §2.2/§3.1): onaylı hero oyun tablosu
## (`data/library/game_buildings.json`, `SettlementTable`) `modules[]` SIRASI = `BuildingColumns.module_idx`
## (yerleşimle AYNI tablo/dizin). Bina bilgisi (ayak izi, yükseklik, üçgen sayısı, pivot) YALNIZ tablodan okunur.
##
## Kapı: kimlik `LibraryGate`ten geçmezse kit'e GİRMEZ (tablo `SettlementTable.filter` ile süzülür) ve mesh isteği de
## her seferinde kapıdan yapılır; onaysız kimlik hiçbir yoldan yüklenmez, `gate.unapproved_ids` sayar.
##
## Kademe eşlemesi (görünüm kademesi -> hero seviyesi): LOD0 kademesi = hero LOD1 mesh'i (258-552 üçgen), LOD1
## kademesi =
## dokulu hero PROXY (30-80 üçgen). Hero LOD0 (1,5-6,7k üçgen) BU PAKETTE ÇİZİLMEZ (ADR-0006 §3.1). Gölge düşüren de
## PROXY'dir. HLOD1 = PROXY şablonu, HLOD2 = kutu; ikisinin rengi PROXY atlasından YÜKLEME ANINDA piştirilir
## (köşe rengi sRGB kodlu: kit `mat_kit_proxy` ile aynı sözleşme; ortalamalar doğrusal uzayda alınır).
##
## Hero palet satırı taşımaz: renk atlas dokusundan gelir; modül başına wall/roof rengi (HLOD2 kutusu) piştirilmiş
## ortalama.

## Görünüm kademesi -> hero seviye adı (`game_buildings.json` `lods.*`).
const LEVEL_FOR_TIER := {BuildingLod.Tier.LOD0: "LOD1", BuildingLod.Tier.LOD1: "PROXY"}
## PROXY şablonu rengi: üçgen UV alanı bu kadar alt üçgene bölünür (N x N), alt üçgen merkezlerinden doku örneklenir.
const BAKE_SUBDIVISIONS := 4
## Çatı/duvar ayrımı: yüzey normalinin Y bileşeni bu eşikten büyükse çatı, mutlak değeri küçükse duvar.
const ROOF_NORMAL_Y := 0.5
const WALL_NORMAL_Y := 0.5
## Çatı tonu verisi (T-062 sanat kapısı B-4): PROXY atlasındaki düz çatılar LOD1 çatı malzemesinden açık kalır;
## listedeki modüllerin çatı üçgenleri, alan ortalaması `flat_roof_target_srgb` olacak biçimde kanal başına
## çarpılır. Onaylı asset ve katalog hash'i değişmez (yalnız yükleme anındaki piştirme).
const ROOF_TONE_PATH := "res://data/view/building_roof_tone.json"

var gate: LibraryGate = null
var count: int = 0
var ids: PackedStringArray = PackedStringArray()
var kinds: PackedStringArray = PackedStringArray()
var families: PackedStringArray = PackedStringArray()
var footprint_w: PackedFloat32Array = PackedFloat32Array()
var footprint_d: PackedFloat32Array = PackedFloat32Array()
## Toplam yükseklik (LOD0 AABB tepe, m) ve saçak yüksekliği (m); saçak bilinmiyorsa toplam.
var height_m: PackedFloat32Array = PackedFloat32Array()
var eave_m: PackedFloat32Array = PackedFloat32Array()
## Görünüm kademesi başına üçgen: `near_tris` = LOD0 kademesi (hero LOD1), `mid_tris` = LOD1 kademesi (hero PROXY).
var near_tris: PackedInt32Array = PackedInt32Array()
var mid_tris: PackedInt32Array = PackedInt32Array()
## 1: modülün PROXY seviyesi tabloda var (LOD1 kademesi/gölge/HLOD1 çizilebilir).
var has_mid: PackedByteArray = PackedByteArray()
var is_landmark: PackedByteArray = PackedByteArray()
## Modül başına pivot kayması (m): `pivot_offset_m`, köşelere eklenir (ayak izi merkezi pivot).
var pivot_offset: PackedVector3Array = PackedVector3Array()
## Piştirilmiş duvar/çatı rengi, sRGB kodlu köşe rengi (HLOD2 kutusu); `from_game_table` ile dolar, aksi halde nötr gri.
var wall_color: PackedColorArray = PackedColorArray()
var roof_color: PackedColorArray = PackedColorArray()
## Modül başına HLOD1 şablonları: PROXY (BuildingKit.ProxyTemplate) ve kutu; mesh yüklenmediyse null.
var proxies: Array = []
var boxes: Array = []
## D-021: cephe/çatı çeşitliliği verisi ve modülün çatısı eğimli mi (düz çatı çatı modu almaz).
var variety: BuildingVariety = BuildingVariety.load_default()
var roof_pitched: PackedByteArray = PackedByteArray()

var _records: Array[Dictionary] = []
var _mesh_cache: Dictionary = {}


## HLOD1 birleştirmede kullanılan, indekssiz üçgen listesi; köşe rengi (sRGB kodlu) şablona piştirilmiştir.
class ProxyTemplate:
	extends RefCounted
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	## D-021: varyant koduna göre yeniden renklendirilmiş köşe renkleri (`BuildingVariety.CODES` adet); boşsa `colors`.
	var variant_colors: Array = []

	func colors_for(code: int) -> PackedColorArray:
		return variant_colors[code] if code > 0 and code < variant_colors.size() else colors

	func triangle_count() -> int:
		return vertices.size() / 3


## Yalnız tablo sözlüğünden (mesh yüklemeden): boyutlar ve tablo. Testler ve başsız denetim için. `table` önce `gate`ten
## süzülür (yerleşimle AYNI idempotent süzme: aynı dizin); `gate` null ise varsayılan kapı yüklenir.
static func from_table(table: Dictionary, gate: LibraryGate = null) -> BuildingKit:
	var kit := BuildingKit.new()
	kit.gate = gate if gate != null else LibraryGate.load_default()
	var approved := SettlementTable.filter(table, kit.gate)
	for e: Dictionary in approved.get("modules", []):
		kit._add_record(e)
	return kit


## Tablo + PROXY şablonları ve piştirilmiş renkler (ana iş parçacığında çağrılır; GLB/atlas okur).
static func from_game_table(table: Dictionary, gate: LibraryGate = null) -> BuildingKit:
	var kit := from_table(table, gate)
	for i in kit.count:
		kit._bake_module(i)
	return kit


func module_index(id: String) -> int:
	return ids.find(id)


## Görünüm kademesi için mesh (pivot normalize, atlas materyalli yüzey); yoksa null. Ana iş parçacığı. İstek kapıdan
## geçer; mesh bir kez yüklenir ve önbelleklenir. Hero LOD0 hiçbir kademeye eşlenmez.
func tier_mesh(module: int, tier: BuildingLod.Tier) -> Mesh:
	if not LEVEL_FOR_TIER.has(tier):
		return null
	return level_mesh(module, str(LEVEL_FOR_TIER[tier]))


## Hero seviyesi ("LOD1" | "PROXY") mesh'i; "LOD0" bilinçli olarak null (çizilmez).
func level_mesh(module: int, level: String) -> Mesh:
	if module < 0 or module >= count or not (level == "LOD1" or level == "PROXY"):
		return null
	var key := "%s/%s" % [ids[module], level]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rec := gate.request(ids[module])   # onaysızsa boş + iz; yükleme yok
	var lods: Variant = rec.get("lods")
	if not (lods is Dictionary) or not (lods as Dictionary).has(level):
		return null
	var mesh := HeroMeshLoader.load_mesh(str(((lods as Dictionary)[level] as Dictionary)["glb"]), pivot_offset[module],
			variety)
	if mesh != null:
		_mesh_cache[key] = mesh
	return mesh


## Modülün kayıt kopyası (kapıdan; ret sayılır): atlas yolları vb. Onaysızsa boş.
func record(module: int) -> Dictionary:
	if module < 0 or module >= count:
		return {}
	return _records[module].duplicate(true)


func _add_record(e: Dictionary) -> void:
	_records.append(e)
	count += 1
	ids.append(str(e["id"]))
	kinds.append(str(e.get("kind", "")))
	families.append(str(e.get("family", "")))
	var fp: Array = e.get("footprint_m", [0.0, 0.0])
	footprint_w.append(float(fp[0]))
	footprint_d.append(float(fp[1]))
	var top := float(e.get("height_m", 0.0))
	height_m.append(top)
	var gp: Dictionary = e.get("generator_params", {})
	var eave: Variant = gp.get("eave_height_m", top)
	eave_m.append(float(eave) if (eave is float or eave is int) else top)
	var lods: Dictionary = e.get("lods", {})
	near_tris.append(int((lods.get("LOD1", {}) as Dictionary).get("tris", 0)))
	mid_tris.append(int((lods.get("PROXY", {}) as Dictionary).get("tris", 0)))
	has_mid.append(1 if lods.has("PROXY") else 0)
	is_landmark.append(1 if str(e.get("kind", "")) == "landmark" else 0)
	var off: Array = e.get("pivot_offset_m", [0.0, 0.0, 0.0])
	pivot_offset.append(Vector3(float(off[0]), float(off[1]), float(off[2])))
	var roof_type := str(gp.get("roof_type", ""))
	roof_pitched.append(1 if (roof_type != "" and roof_type != "flat") else 0)
	wall_color.append(Color(0.5, 0.5, 0.5, 1.0))
	roof_color.append(Color(0.5, 0.5, 0.5, 1.0))
	proxies.append(null)
	boxes.append(null)


## PROXY mesh'i + PROXY atlası -> HLOD1 şablonu, modül duvar/çatı rengi, kutu şablonu.
func _bake_module(module: int) -> void:
	if has_mid[module] != 1:
		return
	var mesh := level_mesh(module, "PROXY") as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var atlas := _proxy_atlas_image(module)
	if atlas == null:
		push_error("BuildingKit: PROXY atlası okunamadı (%s): HLOD renkleri nötr kalır" % ids[module])
	var baked := _make_template(mesh, atlas, _roof_target_for(ids[module]))
	proxies[module] = baked["template"]
	_bake_variants(baked["template"], module)
	wall_color[module] = baked["wall"]
	roof_color[module] = baked["roof"]
	boxes[module] = _make_box(footprint_w[module], footprint_d[module], height_m[module], baked["wall"], baked["roof"])


## D-021: PROXY şablonunun her varyant kodu için köşe renkleri (HLOD1 birleştirmede örnek başına renk hesabı yok).
func _bake_variants(tpl: ProxyTemplate, module: int) -> void:
	tpl.variant_colors = [tpl.colors]
	if not variety.enabled:
		return
	for code in range(1, BuildingVariety.CODES):
		if roof_pitched[module] != 1 and code % BuildingVariety.ROOF_MODES != 0:
			tpl.variant_colors.append(tpl.colors)
			continue
		var cols := PackedColorArray()
		cols.resize(tpl.colors.size())
		for i in range(0, tpl.colors.size() - 2, 3):
			var ny := (tpl.normals[i].y + tpl.normals[i + 1].y + tpl.normals[i + 2].y) / 3.0
			var y := (tpl.vertices[i].y + tpl.vertices[i + 1].y + tpl.vertices[i + 2].y) / 3.0
			var c := variety.recolor(tpl.colors[i], ny, y, code)
			cols[i] = c
			cols[i + 1] = c
			cols[i + 2] = c
		tpl.variant_colors.append(cols)


func _proxy_atlas_image(module: int) -> Image:
	var atlas: Variant = _records[module].get("proxy_atlas")
	if not (atlas is Dictionary):
		return null
	var path := str((atlas as Dictionary).get("path", ""))
	if path.is_empty():
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	return img


## Mesh -> ProxyTemplate (indeks açılır; üçgen sırası mesh sırasıdır: deterministik) + alan ağırlıklı duvar/çatı rengi.
func _make_template(mesh: ArrayMesh, atlas: Image, roof_target: Color = Color(-1.0, -1.0, -1.0)) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var tpl := ProxyTemplate.new()
	var wall_sum := Vector3.ZERO
	var wall_area := 0.0
	var roof_sum := Vector3.ZERO
	var roof_area := 0.0
	for t in range(0, idx.size() - 2, 3):
		var tri_color := _bake_triangle_color(atlas, uvs[idx[t]], uvs[idx[t + 1]], uvs[idx[t + 2]])
		var area := 0.5 * (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]]).length()
		for k in 3:
			tpl.vertices.append(verts[idx[t + k]])
			tpl.normals.append(normals[idx[t + k]])
			tpl.colors.append(tri_color)
		var up := (normals[idx[t]].y + normals[idx[t + 1]].y + normals[idx[t + 2]].y) / 3.0
		var lin := tri_color.srgb_to_linear()   # alan ortalaması doğrusal uzayda
		var rgb := Vector3(lin.r, lin.g, lin.b) * area
		if up > ROOF_NORMAL_Y:
			roof_sum += rgb
			roof_area += area
		elif absf(up) < WALL_NORMAL_Y:
			wall_sum += rgb
			wall_area += area
	if roof_target.r >= 0.0 and roof_area > 0.0:
		_retone_roof(tpl, roof_sum / roof_area, roof_target)
		var tgt := roof_target.srgb_to_linear()
		roof_sum = Vector3(tgt.r, tgt.g, tgt.b) * roof_area
	var wall := _mean_color(wall_sum, wall_area)
	var roof := _mean_color(roof_sum, roof_area)
	if wall_area <= 0.0:
		wall = roof
	if roof_area <= 0.0:
		roof = wall
	return {"template": tpl, "wall": wall, "roof": roof}


## Çatı üçgenlerinin doğrusal rengini hedef/ortalama oranıyla kanal başına çarpar (şablonda yerinde).
static func _retone_roof(tpl: ProxyTemplate, mean_lin: Vector3, target_srgb: Color) -> void:
	var tgt := target_srgb.srgb_to_linear()
	var mult := Vector3(tgt.r / maxf(mean_lin.x, 1.0e-4), tgt.g / maxf(mean_lin.y, 1.0e-4),
			tgt.b / maxf(mean_lin.z, 1.0e-4))
	for i in range(0, tpl.colors.size() - 2, 3):
		if tpl.normals[i].y <= ROOF_NORMAL_Y:
			continue
		var lin := tpl.colors[i].srgb_to_linear()
		var c := Color(minf(lin.r * mult.x, 1.0), minf(lin.g * mult.y, 1.0), minf(lin.b * mult.z, 1.0), 1.0)
		c = c.linear_to_srgb()
		tpl.colors[i] = c
		tpl.colors[i + 1] = c
		tpl.colors[i + 2] = c


## Modülün çatı hedef rengi (sRGB) ya da (-1,-1,-1) = ton ayarı yok. Veri: `ROOF_TONE_PATH`.
static func _roof_target_for(id: String) -> Color:
	var none := Color(-1.0, -1.0, -1.0)
	var text := FileAccess.get_file_as_string(ROOF_TONE_PATH)
	var d: Variant = JSON.parse_string(text)
	if not (d is Dictionary):
		return none
	var mods: Variant = (d as Dictionary).get("modules", [])
	var tgt: Variant = (d as Dictionary).get("flat_roof_target_srgb", [])
	if not (mods is Array) or not (tgt is Array) or (tgt as Array).size() != 3 or not (mods as Array).has(id):
		return none
	return Color(float(tgt[0]) / 255.0, float(tgt[1]) / 255.0, float(tgt[2]) / 255.0, 1.0)


static func _mean_color(sum: Vector3, area: float) -> Color:
	if area <= 0.0:
		return Color(0.5, 0.5, 0.5, 1.0)
	var m := sum / area
	return Color(m.x, m.y, m.z, 1.0).linear_to_srgb()


## Üçgenin UV alanı N x N alt üçgene bölünür, her alt üçgenin merkezinde atlas örneklenir; ortalama DOĞRUSAL uzayda
## alınır
## ve sRGB'ye kodlanır (pencere pikseli tek başına yüzü karartmasın). Atlas yoksa nötr gri.
static func _bake_triangle_color(atlas: Image, a: Vector2, b: Vector2, c: Vector2) -> Color:
	if atlas == null:
		return Color(0.5, 0.5, 0.5, 1.0)
	var n := BAKE_SUBDIVISIONS
	var acc := Vector3.ZERO
	var samples := 0
	var w := atlas.get_width()
	var h := atlas.get_height()
	for i in n:
		for j in n - i:
			# yukarı bakan alt üçgen (i, j) ve (varsa) ters alt üçgen
			var up := [Vector2(i, j), Vector2(i + 1, j), Vector2(i, j + 1)]
			acc += _sample_sub(atlas, w, h, a, b, c, up, n)
			samples += 1
			if i + j < n - 1:
				var down := [Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]
				acc += _sample_sub(atlas, w, h, a, b, c, down, n)
				samples += 1
	var m := acc / float(maxi(samples, 1))
	return Color(m.x, m.y, m.z, 1.0).linear_to_srgb()


static func _sample_sub(atlas: Image, w: int, h: int, a: Vector2, b: Vector2, c: Vector2, corners: Array,
		n: int) -> Vector3:
	var u := Vector2.ZERO
	for p: Vector2 in corners:
		u += _bary_uv(a, b, c, p, n)
	u /= 3.0
	var px := clampi(int(floor(fposmod(u.x, 1.0) * float(w))), 0, w - 1)
	var py := clampi(int(floor(fposmod(u.y, 1.0) * float(h))), 0, h - 1)
	var col := atlas.get_pixel(px, py).srgb_to_linear()
	return Vector3(col.r, col.g, col.b)


static func _bary_uv(a: Vector2, b: Vector2, c: Vector2, p: Vector2, n: int) -> Vector2:
	var fn := float(n)
	var wb := p.x / fn
	var wc := p.y / fn
	return a * (1.0 - wb - wc) + b * wb + c * wc


## Ayak izi x yükseklik kutusu (taban açık: 4 yan + üst), taban merkezi origin; HLOD1 `box` kaynağı.
static func _make_box(w: float, d: float, h: float, wall: Color, roof: Color) -> ProxyTemplate:
	var tpl := ProxyTemplate.new()
	var hx := w * 0.5
	var hz := d * 0.5
	var b: Array[Vector3] = [Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz)]
	var t: Array[Vector3] = []
	for p in b:
		t.append(Vector3(p.x, h, p.z))
	for k in 4:
		var k2 := (k + 1) % 4
		var edge := b[k2] - b[k]
		var n := Vector3(edge.z, 0.0, -edge.x).normalized()
		var mid := (b[k] + b[k2]) * 0.5
		if n.dot(mid) < 0.0:
			n = -n
		BuildingHlod2.emit_tri(tpl.vertices, tpl.normals, tpl.colors, b[k], t[k], t[k2], n, wall)
		BuildingHlod2.emit_tri(tpl.vertices, tpl.normals, tpl.colors, b[k], t[k2], b[k2], n, wall)
	BuildingHlod2.emit_tri(tpl.vertices, tpl.normals, tpl.colors, t[0], t[1], t[2], Vector3.UP, roof)
	BuildingHlod2.emit_tri(tpl.vertices, tpl.normals, tpl.colors, t[0], t[2], t[3], Vector3.UP, roof)
	return tpl
