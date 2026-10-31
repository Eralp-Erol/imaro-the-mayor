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


## T-042b · Yapı doluluğu: {occupied: {parsel: true}, industrial: {parsel: true}} (T0 sütunlarından; yerel yenileme
## bunu her seferinde yeniden taramasın diye çağıran saklar).
static func occupancy(cols: BuildingColumns) -> Dictionary:
	var occupied: Dictionary = {}
	var industrial: Dictionary = {}
	for i in cols.count:
		var pid := cols.parcel_id[i]
		occupied[pid] = true
		if (cols.flags[i] & BuildingColumns.FLAG_INDUSTRY) != 0 or (cols.flags[i] & BuildingColumns.FLAG_PORT_YARD) != 0:
			industrial[pid] = true
	return {"occupied": occupied, "industrial": industrial}


## T-042b · YEREL yenileme (kamulaştırma / geri alma): `world_rect` (+ pay) içindeki pikseller silinir ve o bölgeye
## değen parsellerin boyaması AĞIN GÜNCEL durumuyla yeniden yapılır (`build` ile aynı kural: dolu parsel ya da yeterince
## dolu bloğun parseli boyanır; alınan parsel ağda yoktur, boyanmaz). Boyama yalnız silinen pencereye kırpılır, dışarıya
## taşmaz. Tam `build`den farkı: örtüşen parsellerde "son boyayan kazanır" sırası. `image` yerinde değişir.
## İki aşama (kareye bölünebilsin): `repaint_begin` pencereyi siler ve boyanacak parselleri listeler; `repaint_step`
## bütçe (µs) dolana dek boyar, bitince true döner. `repaint` ikisini art arda çalıştırır (testler).
static func repaint_begin(image: Image, info: Dictionary, net: WorldNetwork, params: Dictionary,
		world_rect: Rect2) -> Dictionary:
	var grow_m := float(params.get("grow_m", 6.0))
	var origin: Vector2 = info["origin"]
	var cell := float(info["cell_m"])
	var w := image.get_width()
	var h := image.get_height()
	var clear_rect := world_rect.grow(grow_m + 2.0 * cell)
	var x0 := clampi(int(floor((clear_rect.position.x - origin.x) / cell)), 0, w - 1)
	var x1 := clampi(int(floor((clear_rect.end.x - origin.x) / cell)), 0, w - 1)
	var y0 := clampi(int(floor((clear_rect.position.y - origin.y) / cell)), 0, h - 1)
	var y1 := clampi(int(floor((clear_rect.end.y - origin.y) / cell)), 0, h - 1)
	var clip := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	image.fill_rect(clip, Color(0.0, 0.0, 0.0, 0.0))
	var variants: Dictionary = params.get("variants", {})
	return {"clip": clip, "pids": net.parcels_in_rect(clear_rect.grow(grow_m + 1.0)), "next": 0, "painted": 0,
			"fills": {}, "origin": origin, "cell": cell, "grow_m": grow_m,
			"fill_min": float(params.get("block_fill_min", 0.35)), "variant_seed": int(variants.get("seed", 0)),
			"by_block": str(variants.get("unit", "parcel")) == "block", "weights": variants.get("residential", {}),
			"t_us": 0}


static func repaint_step(job: Dictionary, image: Image, net: WorldNetwork, occ: Dictionary, budget_us: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var occupied: Dictionary = occ["occupied"]
	var industrial: Dictionary = occ["industrial"]
	var fills: Dictionary = job["fills"]
	var pids: PackedInt32Array = job["pids"]
	var grow_m: float = job["grow_m"]
	var stepped := 0
	while int(job["next"]) < pids.size():
		if stepped > 0 and Time.get_ticks_usec() - t0 >= budget_us:   # en az bir parsel ilerler
			job["t_us"] = int(job["t_us"]) + (Time.get_ticks_usec() - t0)
			return false
		var pid := pids[int(job["next"])]
		job["next"] = int(job["next"]) + 1
		stepped += 1
		var parcel: WorldParcel = net.parcels.get(pid)
		if parcel == null or parcel.outline.size() < 3:
			continue
		var block: WorldBlock = net.blocks.get(parcel.block_id)
		if not fills.has(parcel.block_id):
			fills[parcel.block_id] = _block_fill(block, occupied, industrial)
		var fill: Array = fills[parcel.block_id]
		var in_filled_block := block != null and not block.parcel_ids.is_empty() \
				and float(fill[0]) / float(block.parcel_ids.size()) >= float(job["fill_min"])
		if not occupied.has(pid) and not in_filled_block:
			continue
		var is_ind := industrial.has(pid) or (in_filled_block and int(fill[1]) * 2 >= int(fill[0]) and int(fill[0]) > 0)
		var outline := parcel.outline
		var grown := Geometry2D.offset_polygon(outline, grow_m, Geometry2D.JOIN_MITER)
		if not grown.is_empty():
			outline = grown[0]
		var variant := variant_of(parcel.block_id if bool(job["by_block"]) else int(pid), int(job["variant_seed"]),
				job["weights"])
		_fill_image(image, job["origin"], float(job["cell"]), outline, is_ind, variant, job["clip"])
		job["painted"] = int(job["painted"]) + 1
	job["t_us"] = int(job["t_us"]) + (Time.get_ticks_usec() - t0)
	return true


## Dönüş: {px: silinen/yenilenen piksel, parcels: boyanan parsel, ms}.
static func repaint(image: Image, info: Dictionary, net: WorldNetwork, occ: Dictionary, params: Dictionary,
		world_rect: Rect2) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var job := repaint_begin(image, info, net, params, world_rect)
	repaint_step(job, image, net, occ, 1 << 40)
	return repaint_report(job, (Time.get_ticks_usec() - t0))


static func repaint_report(job: Dictionary, total_us: int) -> Dictionary:
	var clip: Rect2i = job["clip"]
	return {"px": clip.size.x * clip.size.y, "parcels": int(job["painted"]),
			"paint_ms": snappedf(int(job["t_us"]) / 1000.0, 0.1), "ms": snappedf(total_us / 1000.0, 0.1)}


## [dolu parsel sayısı, sanayi parsel sayısı] (`build` ile aynı sayım).
static func _block_fill(block: WorldBlock, occupied: Dictionary, industrial: Dictionary) -> Array:
	var filled := 0
	var ind := 0
	if block != null:
		for pid in block.parcel_ids:
			if occupied.has(pid):
				filled += 1
			if industrial.has(pid):
				ind += 1
	return [filled, ind]


## `_fill` + `_put` eşdeğeri, `Image` üzerinde ve `clip` (piksel) penceresine kırpılı.
static func _fill_image(image: Image, origin: Vector2, cell: float, poly: PackedVector2Array, is_industrial: bool,
		variant: int, clip: Rect2i) -> void:
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for p in poly:
		bmin = Vector2(minf(bmin.x, p.x), minf(bmin.y, p.y))
		bmax = Vector2(maxf(bmax.x, p.x), maxf(bmax.y, p.y))
	var px0 := maxi(int(floor((bmin.x - origin.x) / cell)), clip.position.x)
	var px1 := mini(int(floor((bmax.x - origin.x) / cell)), clip.end.x - 1)
	var py0 := maxi(int(floor((bmin.y - origin.y) / cell)), clip.position.y)
	var py1 := mini(int(floor((bmax.y - origin.y) / cell)), clip.end.y - 1)
	var painted := false
	for y in range(py0, py1 + 1):
		for x in range(px0, px1 + 1):
			var c := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			if Geometry2D.is_point_in_polygon(c, poly):
				_put_pixel(image, x, y, is_industrial, variant)
				painted = true
	if not painted:
		var mid := (bmin + bmax) * 0.5
		var mx := int(floor((mid.x - origin.x) / cell))
		var my := int(floor((mid.y - origin.y) / cell))
		if clip.has_point(Vector2i(mx, my)):
			_put_pixel(image, mx, my, is_industrial, variant)


static func _put_pixel(image: Image, x: int, y: int, is_industrial: bool, variant: int) -> void:
	var old := image.get_pixel(x, y)
	var g := 1.0 if (is_industrial or old.g > 0.99) else 0.0
	var b := 1.0 if (variant == VARIANT_PLAZA and not is_industrial) else 0.0
	var a := 1.0 if (variant == VARIANT_GREEN and not is_industrial) else 0.0
	image.set_pixel(x, y, Color(1.0, g, b, a))


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
