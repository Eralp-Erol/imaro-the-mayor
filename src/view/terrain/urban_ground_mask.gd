class_name UrbanGroundMask
extends RefCounted
## Kent zemini maskesi (T-051 kısım 2, spec §8.2/4 "kent zemini kenttir"): yapı barındıran parsellerin (ve çoğu dolu
## blokların boş parsellerinin) ayak izinden BİR KEZ hesaplanan düşük çözünürlüklü RGBA8 maske. R = kent zemini
## kaplaması [0,1], G = sanayi/avlu bayrağı [0,1], B = döşeme (plaza_stone_a) seçimi, A = yeşil (grass_green) seçimi;
## B=A=0 -> dirt_courtyard (T-062 A4: parsel/blok kimliği hash'iyle, veri güdümlü ağırlıklar; aşağıda `variant_of`).
## Arazi gölgelendiricisi bunu dünya x/z'den örnekler; yeni malzeme,
## draw call ya da kare-başı iş YOK. Kaynak: WorldNetwork parselleri + BuildingColumns (sihirli koordinat yok, Q-015).
## Parametreler `data/view/terrain_look.json` "urban.mask". Saf hesap (Node/RenderingServer yok): iş parçacığı güvenli.

## Seçim kodları (`variant_of`).
const VARIANT_PLAZA := 0
const VARIANT_DIRT := 1
const VARIANT_GREEN := 2


## Saf, deterministik 32-bit karma [0, 1): aynı (kimlik, tohum) -> aynı değer (`ViewHash`).
static func hash01(id: int, variant_seed: int) -> float:
	return ViewHash.hash01(id, variant_seed)


## Konut zemini seçimi: `weights` {plaza, dirt, green} (toplam 1'e normalleşir). Aynı kimlik -> aynı seçim.
static func variant_of(id: int, variant_seed: int, weights: Dictionary) -> int:
	var plaza := maxf(float(weights.get("plaza", 0.0)), 0.0)
	var dirt := maxf(float(weights.get("dirt", 1.0)), 0.0)
	var green := maxf(float(weights.get("green", 0.0)), 0.0)
	var total := plaza + dirt + green
	if total <= 0.0:
		return VARIANT_DIRT
	var u := hash01(id, variant_seed) * total
	if u < plaza:
		return VARIANT_PLAZA
	if u < plaza + dirt:
		return VARIANT_DIRT
	return VARIANT_GREEN


## Sonuç: {"image": Image (RGBA8), "origin": Vector2, "size": Vector2, "cell_m": float, "parcels": int, "ms": float}
## ya da boş sözlük (yapı yok).
static func build(net: WorldNetwork, cols: BuildingColumns, params: Dictionary) -> Dictionary:
	if net == null or cols == null or cols.count == 0:
		return {}
	var t0 := Time.get_ticks_usec()
	var grow_m := float(params.get("grow_m", 6.0))
	var margin_m := float(params.get("margin_m", 300.0))
	var max_px := int(params.get("max_px", 2048))
	var min_cell := float(params.get("min_cell_m", 10.0))
	var block_fill_min := float(params.get("block_fill_min", 0.35))
	var variants: Dictionary = params.get("variants", {})
	var variant_seed := int(variants.get("seed", 0))
	var by_block := str(variants.get("unit", "parcel")) == "block"
	var weights: Dictionary = variants.get("residential", {})

	# Parsel -> sanayi bayrağı (en az bir sanayi yapısı) ve dolu parsel kümesi.
	var industrial: Dictionary = {}
	var occupied: Dictionary = {}
	for i in cols.count:
		var pid := cols.parcel_id[i]
		occupied[pid] = true
		if (cols.flags[i] & BuildingColumns.FLAG_INDUSTRY) != 0 or (cols.flags[i] & BuildingColumns.FLAG_PORT_YARD) != 0:
			industrial[pid] = true

	# Blok doluluğu: yeterince dolu bloğun boş parselleri de kent zemini sayılır (boş arsa = toprak/avlu).
	var paint: Dictionary = {}
	for pid in occupied:
		paint[pid] = true
	for bid in net.blocks:
		var block: WorldBlock = net.blocks[bid]
		if block.parcel_ids.is_empty():
			continue
		var filled := 0
		var ind := 0
		for pid in block.parcel_ids:
			if occupied.has(pid):
				filled += 1
			if industrial.has(pid):
				ind += 1
		if float(filled) / float(block.parcel_ids.size()) >= block_fill_min:
			for pid in block.parcel_ids:
				paint[pid] = true
				if ind * 2 >= filled and filled > 0 and not industrial.has(pid):
					industrial[pid] = true

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var polys: Array[PackedVector2Array] = []
	var ind_flags := PackedByteArray()
	var variant_codes := PackedByteArray()
	for pid in paint:
		var parcel: WorldParcel = net.parcels.get(pid)
		if parcel == null or parcel.outline.size() < 3:
			continue
		var outline := parcel.outline
		var grown := Geometry2D.offset_polygon(outline, grow_m, Geometry2D.JOIN_MITER)
		if not grown.is_empty():
			outline = grown[0]
		polys.append(outline)
		ind_flags.append(1 if industrial.has(pid) else 0)
		variant_codes.append(variant_of(parcel.block_id if by_block else int(pid), variant_seed, weights))
		for p in outline:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	if polys.is_empty():
		return {}
	lo -= Vector2(margin_m, margin_m)
	hi += Vector2(margin_m, margin_m)
	var extent := hi - lo
	var cell := maxf(min_cell, maxf(extent.x, extent.y) / float(max_px))
	var w := int(ceil(extent.x / cell))
	var h := int(ceil(extent.y / cell))
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for k in polys.size():
		_fill(data, w, h, lo, cell, polys[k], ind_flags[k] == 1, variant_codes[k])
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	return {"image": image, "origin": lo, "size": Vector2(w, h) * cell, "cell_m": cell, "parcels": polys.size(),
			"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}


## Çokgeni piksel merkezi içindeyse boyar (R = 255; sanayi ise G = 255; B/A = döşeme/yeşil seçimi).
## Çok küçük çokgen en az bir piksel boyar.
static func _fill(data: PackedByteArray, w: int, h: int, origin: Vector2, cell: float, poly: PackedVector2Array,
		is_industrial: bool, variant: int) -> void:
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for p in poly:
		bmin = Vector2(minf(bmin.x, p.x), minf(bmin.y, p.y))
		bmax = Vector2(maxf(bmax.x, p.x), maxf(bmax.y, p.y))
	var x0 := clampi(int(floor((bmin.x - origin.x) / cell)), 0, w - 1)
	var x1 := clampi(int(floor((bmax.x - origin.x) / cell)), 0, w - 1)
	var y0 := clampi(int(floor((bmin.y - origin.y) / cell)), 0, h - 1)
	var y1 := clampi(int(floor((bmax.y - origin.y) / cell)), 0, h - 1)
	var painted := false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if Geometry2D.is_point_in_polygon(c, poly):
				_put(data, (y * w + x) * 4, is_industrial, variant)
				painted = true
	if not painted:
		var mid := (bmin + bmax) * 0.5
		var mx := clampi(int(floor((mid.x - origin.x) / cell)), 0, w - 1)
		var my := clampi(int(floor((mid.y - origin.y) / cell)), 0, h - 1)
		_put(data, (my * w + mx) * 4, is_industrial, variant)


static func _put(data: PackedByteArray, o: int, is_industrial: bool, variant: int) -> void:
	data[o] = 255
	if is_industrial:
		data[o + 1] = 255
	elif data[o + 1] != 255:
		data[o + 1] = 0
	# Seçim: sanayi parselinde yok (gravel); konutta son boyayan parsel kazanır (deterministik sıra).
	data[o + 2] = 255 if (variant == VARIANT_PLAZA and not is_industrial) else 0
	data[o + 3] = 255 if (variant == VARIANT_GREEN and not is_industrial) else 0
