class_name BuildingChunkBuilder
extends RefCounted
## Bir chunk'ın render verisini üretir (T-012; T-062 A3): sütunlar -> MultiMesh tamponları (LOD0/LOD1 kademesi ortak) +
## HLOD1 birleşik mesh verisi. SAF ve iş parçacığı güvenli: Node/Mesh/RenderingServer yok; yalnız Packed* dizileri,
## `BuildingKit` tablosu ve WorldData okuması. Determinizm: aynı sütun + aynı dünya -> aynı bayt.
## Hero örneği yalnız dönüşümdür (3x4); palet/özel veri yok: renk modülün atlas dokusundan gelir.

const FLOATS_PER_INSTANCE := 12
## D-021: dönüşümün ardından 4 float özel veri (çatı modu, açık cephe, parlaklık sapması, 0): MultiMesh tamponu aralığı.
const CUSTOM_FLOATS := 4
const INSTANCE_STRIDE := FLOATS_PER_INSTANCE + CUSTOM_FLOATS


static func build_cell(cols: BuildingColumns, plan: BuildingChunkPlan, key: Vector2i, kit: BuildingKit,
		world: WorldData, config: BuildingViewConfig) -> BuildingCellData:
	var data := BuildingCellData.new()
	data.key = key
	data.origin = plan.cell_origin(key)
	var idx := plan.indices(key)
	var by_module: Dictionary = {}
	var kept := PackedInt32Array()
	var kept_ord := PackedInt32Array()
	var base_y := PackedFloat32Array()
	for ord in idx.size():
		var i := idx[ord]
		var m := cols.module_idx[i]
		var by := BuildingGround.base_y(world, cols.x[i], cols.z[i], cols.yaw[i], kit.footprint_w[m] * 0.5,
				kit.footprint_d[m] * 0.5, config.coast_margin_m)
		if is_nan(by):
			data.dropped += 1
			continue
		if not by_module.has(m):
			by_module[m] = []   # Array (referans); Packed* sözlükte kopyalanır
		(by_module[m] as Array).append(kept.size())
		kept.append(i)
		kept_ord.append(ord)
		base_y.append(by)
	data.kept = kept
	data.kept_ord = kept_ord
	data.base_y = base_y
	data.variants = _pick_variants(cols, kept, kit)
	var module_keys: Array = by_module.keys()
	module_keys.sort()
	for m: int in module_keys:
		var rows := PackedInt32Array(by_module[m] as Array)
		data.modules.append(m)
		data.counts.append(rows.size())
		data.buffers.append(_instance_buffer(cols, kept, base_y, rows, data.origin, data.variants, kit.variety))
		data.lod0_tris += kit.near_tris[m] * rows.size()
		data.lod1_tris += (kit.mid_tris[m] if kit.has_mid[m] == 1 else kit.near_tris[m]) * rows.size()
	if config.build_hlod1:
		_merge_hlod1(data, cols, kit, config)
	return data


## Örnek başına 12 float: 3x4 dönüşüm (satır öncelikli, `Basis(UP, yaw)` ölçek 1). Pivot ayak izi merkezidir
## (mesh `BuildingKit`te normalize edilmiştir), yani `x/z` doğrudan yerleşim merkezidir.
static func _instance_buffer(cols: BuildingColumns, kept: PackedInt32Array, base_y: PackedFloat32Array,
		rows: PackedInt32Array, origin: Vector2, variants: PackedInt32Array, variety: BuildingVariety) \
		-> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(rows.size() * INSTANCE_STRIDE)
	var o := 0
	for r in rows:
		var i := kept[r]
		var c := cos(cols.yaw[i])
		var s := sin(cols.yaw[i])
		buf[o] = c
		buf[o + 1] = 0.0
		buf[o + 2] = s
		buf[o + 3] = cols.x[i] - origin.x
		buf[o + 4] = 0.0
		buf[o + 5] = 1.0
		buf[o + 6] = 0.0
		buf[o + 7] = base_y[r]
		buf[o + 8] = -s
		buf[o + 9] = 0.0
		buf[o + 10] = c
		buf[o + 11] = cols.z[i] - origin.y
		var cd := variety.custom_data(variants[r], cols.bright[i])
		buf[o + 12] = cd.r
		buf[o + 13] = cd.g
		buf[o + 14] = cd.b
		buf[o + 15] = 0.0
		o += INSTANCE_STRIDE
	return buf


## D-021: örnek başına varyant kodu (kept ile paralel). Parsel kimliği + modülden deterministik; aynı modülün
## `reroll_radius_m` içindeki komşusuyla aynı kodu alırsa yeniden çekilir (yan yana tekrar kırılır). Hücre-yerel:
## yalnız hücre içeriğine bağlı, sütun sırası (hücre planı sırası) deterministik.
static func _pick_variants(cols: BuildingColumns, kept: PackedInt32Array, kit: BuildingKit) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(kept.size())
	var v := kit.variety
	if not v.enabled:
		return out
	var radius := maxf(v.reroll_radius_m, 1.0)
	var grid: Dictionary = {}
	for j in kept.size():
		var i := kept[j]
		var m := cols.module_idx[i]
		var fam := kit.families[m]
		var pitched := kit.roof_pitched[m] == 1
		var gx := int(floor(cols.x[i] / radius))
		var gz := int(floor(cols.z[i] / radius))
		var code := 0
		for salt in range(maxi(v.reroll_tries, 1)):
			code = v.pick(fam, cols.parcel_id[i], m, pitched, salt)
			if not _clashes(grid, gx, gz, Vector2(cols.x[i], cols.z[i]), m, code, radius):
				break
		out[j] = code
		var key := Vector2i(gx, gz)
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(Vector4(cols.x[i], cols.z[i], float(m), float(code)))
	return out


static func _clashes(grid: Dictionary, gx: int, gz: int, pos: Vector2, m: int, code: int, radius: float) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var list: Array = grid.get(Vector2i(gx + dx, gz + dz), [])
			for e: Vector4 in list:
				if int(e.w) == code and int(e.z) == m and Vector2(e.x, e.y).distance_to(pos) <= radius:
					return true
	return false


## HLOD1: kaynak şablonlar (`config.hlod1_source`: "proxy" = PROXY mesh'i, "box" = ayak izi kutusu) hücre içinde tek
## mesh'te birleştirilir (indekssiz). Renk şablona piştirilmiştir (PROXY atlası, sRGB kodlu): örnek başına renk
## hesabı yok.
static func _merge_hlod1(data: BuildingCellData, cols: BuildingColumns, kit: BuildingKit,
		config: BuildingViewConfig) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var templates: Array = kit.boxes if config.hlod1_source == BuildingViewConfig.HLOD1_BOX else kit.proxies
	for j in data.kept.size():
		var i := data.kept[j]
		var m := cols.module_idx[i]
		var tpl: BuildingKit.ProxyTemplate = templates[m]
		if tpl == null:
			continue
		var basis := Basis(Vector3.UP, cols.yaw[i])
		var xf := Transform3D(basis, Vector3(cols.x[i] - data.origin.x, data.base_y[j], cols.z[i] - data.origin.y))
		verts.append_array(xf * tpl.vertices)
		normals.append_array(Transform3D(basis, Vector3.ZERO) * tpl.normals)
		colors.append_array(tpl.colors_for(data.variants[j]))
	data.hlod1_vertices = verts
	data.hlod1_normals = normals
	data.hlod1_colors = colors
