class_name UrbanGroundMask
extends RefCounted
## Kent zemini maskesi (T-051 kısım 2, spec §8.2/4 "kent zemini kenttir"): yapı barındıran parsellerin (ve çoğu dolu
## blokların boş parsellerinin) ayak izinden BİR KEZ hesaplanan düşük çözünürlüklü RG8 maske. R = kent zemini
## kaplaması [0,1], G = sanayi/avlu bayrağı [0,1]. Arazi gölgelendiricisi bunu dünya x/z'den örnekler; yeni malzeme,
## draw call ya da kare-başı iş YOK. Kaynak: WorldNetwork parselleri + BuildingColumns (sihirli koordinat yok, Q-015).
## Parametreler `data/view/terrain_look.json` "urban.mask". Saf hesap (Node/RenderingServer yok): iş parçacığı güvenli.

## Sonuç: {"image": Image (RG8), "origin": Vector2, "size": Vector2, "cell_m": float, "parcels": int, "ms": float}
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
	data.resize(w * h * 2)
	for k in polys.size():
		_fill(data, w, h, lo, cell, polys[k], ind_flags[k] == 1)
	var image := Image.create_from_data(w, h, false, Image.FORMAT_RG8, data)
	return {"image": image, "origin": lo, "size": Vector2(w, h) * cell, "cell_m": cell, "parcels": polys.size(),
			"ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)}


## Çokgeni piksel merkezi içindeyse boyar (R = 255; sanayi ise G = 255). Çok küçük çokgen en az bir piksel boyar.
static func _fill(data: PackedByteArray, w: int, h: int, origin: Vector2, cell: float, poly: PackedVector2Array,
		is_industrial: bool) -> void:
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
				_put(data, (y * w + x) * 2, is_industrial)
				painted = true
	if not painted:
		var mid := (bmin + bmax) * 0.5
		var mx := clampi(int(floor((mid.x - origin.x) / cell)), 0, w - 1)
		var my := clampi(int(floor((mid.y - origin.y) / cell)), 0, h - 1)
		_put(data, (my * w + mx) * 2, is_industrial)


static func _put(data: PackedByteArray, o: int, is_industrial: bool) -> void:
	data[o] = 255
	if is_industrial:
		data[o + 1] = 255
	elif data[o + 1] != 255:
		data[o + 1] = 0
