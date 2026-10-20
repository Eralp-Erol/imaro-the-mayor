class_name BuildingChunkBuilder
extends RefCounted
## Bir chunk'ın render verisini üretir (T-012): sütunlar -> MultiMesh tamponları (LOD0/LOD1 ortak) + HLOD1 birleşik
## mesh verisi. SAF ve iş parçacığı güvenli: Node/Mesh/RenderingServer yok; yalnız Packed* dizileri, `BuildingKit`
## tablosu ve WorldData okuması. Determinizm: aynı sütun + aynı dünya -> aynı bayt.

const FLOATS_PER_INSTANCE := 16
## HLOD1 renk önbelleğinde parlaklık kovası (HLOD1'de ±%6 parlaklık ayırt edilmez; önbellek isabetini artırır).
const HLOD_BRIGHT_BUCKETS := 8


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
	var module_keys: Array = by_module.keys()
	module_keys.sort()
	for m: int in module_keys:
		var rows := PackedInt32Array(by_module[m] as Array)
		data.modules.append(m)
		data.counts.append(rows.size())
		data.buffers.append(_instance_buffer(cols, kept, base_y, rows, data.origin))
		data.lod0_tris += kit.lod0_tris[m] * rows.size()
		data.lod1_tris += (kit.lod1_tris[m] if kit.has_lod1[m] == 1 else kit.lod0_tris[m]) * rows.size()
	if config.build_hlod1:
		_merge_hlod1(data, cols, kit, config)
	return data


## Örnek başına 16 float: 3x4 dönüşüm (satır öncelikli, `Basis(UP, yaw)` ölçek 1) + özel veri
## (duvar, çatı, aksan satırı, parlaklık) / 32 (`KitMaterial.encode_instance`).
static func _instance_buffer(cols: BuildingColumns, kept: PackedInt32Array, base_y: PackedFloat32Array,
		rows: PackedInt32Array, origin: Vector2) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(rows.size() * FLOATS_PER_INSTANCE)
	var o := 0
	var inv := 1.0 / KitMaterial.INSTANCE_SCALE
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
		buf[o + 12] = cols.wall_row[i] * inv
		buf[o + 13] = cols.roof_row[i] * inv
		buf[o + 14] = cols.accent_row[i] * inv
		buf[o + 15] = cols.bright_factor(i) * inv
		o += FLOATS_PER_INSTANCE
	return buf


## PROXY şablonlarını hücre içinde tek mesh'te birleştirir (indekssiz; renk köşeye pişirilir).
static func _merge_hlod1(data: BuildingCellData, cols: BuildingColumns, kit: BuildingKit,
		config: BuildingViewConfig) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var color_cache: Dictionary = {}
	for j in data.kept.size():
		var i := data.kept[j]
		var m := cols.module_idx[i]
		var tpl: BuildingKit.ProxyTemplate = kit.proxies[m]
		if tpl == null:
			continue
		var basis := Basis(Vector3.UP, cols.yaw[i])
		var xf := Transform3D(basis, Vector3(cols.x[i] - data.origin.x, data.base_y[j], cols.z[i] - data.origin.y))
		verts.append_array(xf * tpl.vertices)
		normals.append_array(Transform3D(basis, Vector3.ZERO) * tpl.normals)
		var bucket := clampi(int(float(cols.bright[i]) / 256.0 * HLOD_BRIGHT_BUCKETS), 0, HLOD_BRIGHT_BUCKETS - 1)
		var ck := ((m * 32 + cols.wall_row[i]) * 32 + cols.roof_row[i]) * 32 + cols.accent_row[i]
		ck = ck * HLOD_BRIGHT_BUCKETS + bucket
		if not color_cache.has(ck):
			var bright_mul := BuildingColumns.BRIGHT_MIN + (BuildingColumns.BRIGHT_MAX - BuildingColumns.BRIGHT_MIN) \
					* (float(bucket) + 0.5) / float(HLOD_BRIGHT_BUCKETS)
			color_cache[ck] = template_colors(kit, tpl, cols.wall_row[i], cols.roof_row[i], cols.accent_row[i],
					bright_mul, config.proxy_colors_linear)
		colors.append_array(color_cache[ck] as PackedColorArray)
	data.hlod1_vertices = verts
	data.hlod1_normals = normals
	data.hlod1_colors = colors


## Şablonun köşe renkleri: grup başına tek renk (palet satırı x parça çarpanı x gölge x parlaklık).
static func template_colors(kit: BuildingKit, tpl: BuildingKit.ProxyTemplate, wall: int, roof: int, accent: int,
		bright_mul: float, linear: bool = false) -> PackedColorArray:
	var out := PackedColorArray()
	for g in tpl.group_len.size():
		var row := tpl.group_row[g]
		match tpl.group_slot[g]:
			BuildingKit.SLOT_WALL:
				row = wall
			BuildingKit.SLOT_ROOF:
				row = roof
			BuildingKit.SLOT_ACCENT:
				row = accent
		var c := kit.shaded(row, tpl.group_mul[g] * bright_mul)
		if linear:
			c = c.srgb_to_linear()
		var block := PackedColorArray()
		block.resize(tpl.group_len[g])
		block.fill(c)
		out.append_array(block)
	return out
