class_name KitLabLayout
extends RefCounted
## kit_lab test mahallesi üreticisi (DEV; T-005 yerleşimcisi DEĞİL, coğrafyadan bağımsız). Sabit tohumlu, spec
## 3.3
## kurallarıyla: bitişik nizam sıraları, komşu aynı (mesh+duvar) yok, 9'lu pencerede ≥3 mesh ve ≥3 duvar
## rengi,
## yön yalnız 0/180°, XZ ölçeği 0,90–1,15, Y 0,95–1,05, ayna yok. Saat kulesi (0,0)'da, çevresinde ≥52 ×
## 60 m meydan.
## Çıktı yalnız veridir (placements/props); çizim kit_lab.gd'de.

const STREET_W := 12.0
const HALF_STREET := 6.0
const AREA := Rect2(-600.0, -330.0, 1200.0, 680.0)
const PLAZA := Rect2(-30.0, -26.0, 60.0, 52.0)
const TOWER_FRAME_RADIUS := 150.0
const TOWER_FRAME_MAX_TOP := 17.7   ## 23 / 1.3: çerçeve parapet üstü bu değeri aşmaz (spec 4)
const Y_SCALE_MAX := 1.05
const PARAPET_M := 0.9
const CROSS_GAP_M := 12.0
const WALL_CAP := {"W3": 0.15, "W4": 0.10, "W6": 0.10, "W7": 0.10}

## Bölge → [aile, ağırlık]. Aile içinde kimlikler eşit ağırlıklı (gf varyantı bölge ayarıyla).
const ZONE_FAMILY_WEIGHTS := {
	&"center": [["res_mid", 0.38], ["res_old", 0.25], ["res_late", 0.23], ["civ_hall", 0.02], ["res_house", 0.05]],
	&"dense": [["res_mid", 0.40], ["res_late", 0.27], ["res_old", 0.19], ["civ_hall", 0.015], ["res_house", 0.025]],
	&"historic": [["res_old", 0.66], ["res_mid", 0.05], ["res_house", 0.29]],
	&"village": [["res_house", 0.60], ["res_old", 0.40]],
	&"industry": [["ind_shed", 0.50], ["ind_heritage", 0.16], ["res_late", 0.12], ["res_mid", 0.16],
			["res_house", 0.06]],
}
## Aile içi kimlik çarpanı (testere dişi / kurşun "diğer" payını ve nadir landmark-benzeri yapıları kısar).
const ID_WEIGHT := {"bld_ind_shed_b": 0.3, "bld_ind_heritage_b": 0.35, "bld_civ_hall_b": 0.7, "bld_res_old_c": 0.8,
		"bld_res_old_c_gf": 0.8}
## Çatı malzemesi satır ağırlıkları (satır adı → ağırlık). R3 en doygun: kiremit alanının ≤ %40'ı.
const ROOF_ROW_WEIGHTS := {
	"R1": 0.68, "R2": 0.32, "R3": 0.30, "R4": 0.42, "R5": 0.28, "R6": 0.50, "R7": 0.50, "R8": 1.0,
}
## Köy/kasaba evlerinde sac çatı payı düşük (spec 3.2: %5–15).
const HOUSE_ROOF_ROW_WEIGHTS := {"R3": 0.30, "R4": 0.42, "R5": 0.28, "R6": 0.17}
const WALL_ROW_WEIGHTS := {
	"W1": 0.28, "W2": 0.22, "W3": 0.09, "W4": 0.05, "W5": 0.12, "W6": 0.06, "W7": 0.06, "W8": 0.10, "W9": 0.12,
	"W10": 1.0, "W11": 1.0, "W12": 0.5, "W13": 0.5,
}

var lib: KitLibrary
var rng := RandomNumberGenerator.new()
var placements: Array[Dictionary] = []
var props: Array[Dictionary] = []
var streets: Array[Dictionary] = []     ## {z, x0, x1, depth_n, depth_s}
var rows: Array[Array] = []             ## satır başına placements indeksleri (x sırasıyla)
var tower: Dictionary = {}
## kit_street kamera koridoru: sokak z'si + odak x'i; kamera çevresindeki 14 m'lik ağaçlar koridordan
## çıkarılır.
var street_view: Dictionary = {}
var wall_index: Dictionary = {}         ## satır adı → indeks (önbellek)
var _used_cells: Dictionary = {}        ## 200 m hücre → kullanılmış (mesh|duvar) kombinasyonları


func generate(library: KitLibrary, seed_value: int = 20261020) -> void:
	lib = library
	rng.seed = seed_value
	placements.clear()
	props.clear()
	streets.clear()
	rows.clear()
	_used_cells.clear()
	_make_streets()
	_pick_street_view()
	for s in streets:
		_fill_row(s, true)
		_fill_row(s, false)
	_make_props()
	var t := lib.entry("bld_lmk_clocktower")
	tower = {"id": "bld_lmk_clocktower", "pos": Vector3.ZERO, "rot": 0.0, "scale": Vector3.ONE,
			"wall": _row("W11"), "roof": _row("R8"), "accent": _row("A1"), "bright": 1.0, "zone": &"square",
			"entry": t}


static func zone_at(x: float, z: float) -> StringName:
	if sqrt(x * x + z * z) < TOWER_FRAME_RADIUS:
		return &"center"
	if z > 230.0:
		return &"industry"
	if x < -170.0 and x > -340.0 and absf(z) < 260.0:
		return &"historic"
	if x > 440.0:
		return &"village"
	return &"dense"


static func plot_depth(z: float) -> float:
	return 40.0 if z > 190.0 else 20.0


func _row(row_name: String) -> int:
	if not wall_index.has(row_name):
		wall_index[row_name] = KitMaterial.row_index(row_name)
	return wall_index[row_name]


func _pick_street_view() -> void:
	var best: Dictionary = streets[0]
	for s in streets:
		if absf(float(s["z"])) < absf(float(best["z"])):
			best = s
	street_view = {"z": float(best["z"]), "focus_x": 130.0}


func _make_streets() -> void:
	var z := AREA.position.y + 26.0
	while z < AREA.end.y - 20.0:
		var dn := plot_depth(z - 40.0)
		var ds := plot_depth(z + 40.0)
		streets.append({"z": z, "x0": AREA.position.x, "x1": AREA.end.x, "depth_n": dn, "depth_s": ds})
		var next_dn := plot_depth(z + HALF_STREET + ds + 30.0)
		z += HALF_STREET + ds + next_dn + HALF_STREET


## Bir sokak şeridinin bir tarafını (kuzey = z küçük, ön yüz +Z, dönüş 0; güney = dönüş 180°)
## doldurur.
func _fill_row(street: Dictionary, north: bool) -> void:
	var depth: float = street["depth_n"] if north else street["depth_s"]
	var sz: float = street["z"]
	var row_ids: Array = []
	var hist: Array[Dictionary] = []
	var x: float = street["x0"] + rng.randf_range(0.0, 6.0)
	var next_gap_at: float = x + rng.randf_range(70.0, 130.0)
	while x < street["x1"] - 8.0:
		var z_front := sz - HALF_STREET if north else sz + HALF_STREET
		var zone := zone_at(x + 8.0, z_front)
		var strip_main := absf(sz) < 60.0
		var pick := _pick(zone, hist, strip_main, x + 8.0, z_front, depth)
		if pick.is_empty():
			x += 6.0
			continue
		var e: Dictionary = pick["entry"]
		var fp: Array = e["footprint_m"]
		var sx := rng.randf_range(0.90, 1.15)
		var sd := rng.randf_range(0.90, 1.15)
		sd = minf(sd, depth / float(fp[1]))
		var sy := rng.randf_range(0.95, 1.05)
		var w := float(fp[0]) * sx
		var d := float(fp[1]) * sd
		var cx := x + w * 0.5
		var cz := z_front - d * 0.5 if north else z_front + d * 0.5
		var rect := Rect2(cx - w * 0.5, cz - d * 0.5, w, d).grow(1.0)
		if rect.intersects(PLAZA) or cx + w * 0.5 > street["x1"]:
			x += w + 1.0
			continue
		var p := {
			"id": pick["id"], "entry": e, "pos": Vector3(cx, 0.0, cz), "rot": 0.0 if north else PI,
			"scale": Vector3(sx, sy, sd), "wall": pick["wall"], "roof": pick["roof"], "accent": pick["accent"],
			"bright": 1.0 + rng.randf_range(-0.06, 0.06), "zone": zone, "row": rows.size(),
		}
		placements.append(p)
		row_ids.append(placements.size() - 1)
		hist.append(p)
		x += w + _gap_for(e, zone)
		if x > next_gap_at:
			x += CROSS_GAP_M
			next_gap_at = x + rng.randf_range(70.0, 130.0)
			hist.clear()
	rows.append(row_ids)


func _gap_for(e: Dictionary, zone: StringName) -> float:
	var fam := str(e["family"])
	if fam == "res_house":
		return rng.randf_range(3.0, 5.0)
	if fam in ["ind_shed", "ind_heritage"]:
		return rng.randf_range(6.0, 12.0)
	if fam == "civ_hall":
		return rng.randf_range(3.0, 6.0)
	if zone == &"village":
		return rng.randf_range(2.0, 4.0) + (rng.randf_range(4.0, 16.0) if rng.randf() < 0.55 else 0.0)
	return rng.randf_range(0.0, 0.4)


## Aday seçimi: bölge ağırlıkları + spec 3.3 kısıtları (komşu aynı değil, 9'lu pencerede ≥3 mesh / ≥3
## duvar).
func _pick(zone: StringName, hist: Array[Dictionary], strip_main: bool, x: float, z: float, depth: float) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var near_tower := sqrt(x * x + z * z) < TOWER_FRAME_RADIUS + 20.0
	for fw in ZONE_FAMILY_WEIGHTS[zone]:
		var fam: String = fw[0]
		var fam_w: float = fw[1]
		if fam_w <= 0.0:
			continue
		var ids := lib.family_ids(fam)
		for id in ids:
			var e := lib.entry(id)
			var top := float(e["eave_height_m"]) + PARAPET_M
			if near_tower and top * Y_SCALE_MAX > TOWER_FRAME_MAX_TOP:
				continue
			if float(e["footprint_m"][1]) > depth + 0.01 and float(e["footprint_m"][1]) * 0.9 > depth:
				continue
			var w := fam_w / ids.size() * float(ID_WEIGHT.get(id, 1.0))
			if bool(e["gf"]):
				w *= 2.2 if strip_main else (0.3 if zone == &"village" else 0.8)
			candidates.append({"id": id, "entry": e, "w": w})
	if candidates.is_empty():
		return {}
	var order := _weighted_order(candidates)
	var prev: Dictionary = hist.back() if not hist.is_empty() else {}
	var cell := Vector2i(floori(x / 200.0), floori(z / 200.0))
	# Sıkılık kademeleri: 0 = tüm kurallar (+ pencerede benzersiz kombinasyon + kat çeşitliliği), 1 = kat çeşitliliği
	# gevşer, 2 = yalnız komşu/9'lu pencere kuralları.
	for level in 3:
		for c in order:
			if not prev.is_empty() and prev["id"] == c["id"]:
				continue
			for attempt in 5:
				var wall := _pick_row(c["entry"]["palette"]["wall_rows"], WALL_ROW_WEIGHTS)
				if not prev.is_empty() and prev["wall"] == wall:
					continue
				if not _window_ok(hist, c["id"], wall):
					continue
				var combo := "%s|%d" % [c["id"], wall]
				var used: Dictionary = _used_cells.get(cell, {})
				if level < 2 and used.has(combo):
					continue
				if level < 1 and not _floors_ok(hist, c["entry"]):
					continue
				used[combo] = true
				_used_cells[cell] = used
				return {
					"id": c["id"], "entry": c["entry"], "wall": wall,
					"roof": _pick_row(c["entry"]["palette"]["roof_rows"],
							HOUSE_ROOF_ROW_WEIGHTS if str(c["entry"]["family"]) == "res_house" else ROOF_ROW_WEIGHTS),
					"accent": _pick_row(c["entry"]["palette"]["accent_rows"], {}),
				}
	return {}


## Konut sıralarında kat sayısı çeşitliliği (spec 3.3: orta yoğun blokta std ≥ 1 kat): son 8 konut + aday.
func _floors_ok(hist: Array[Dictionary], entry: Dictionary) -> bool:
	if not str(entry["family"]) in ["res_mid", "res_old", "res_late"]:
		return true
	var f: Array[float] = [float(entry["floors"])]
	var i := hist.size() - 1
	while i >= 0 and f.size() < 9:
		var he: Dictionary = hist[i]["entry"]
		if str(he["family"]) in ["res_mid", "res_old", "res_late"]:
			f.append(float(he["floors"]))
		i -= 1
	if f.size() < 6:
		return true
	var mean := 0.0
	for v in f:
		mean += v
	mean /= f.size()
	var acc := 0.0
	for v in f:
		acc += (v - mean) * (v - mean)
	return sqrt(acc / f.size()) >= 1.5


func _window_ok(hist: Array[Dictionary], id: String, wall: int) -> bool:
	var ids := {id: true}
	var walls := {wall: true}
	var start := maxi(0, hist.size() - 8)
	for i in range(start, hist.size()):
		ids[hist[i]["id"]] = true
		walls[hist[i]["wall"]] = true
	if hist.size() < 8:
		return true
	return ids.size() >= 3 and walls.size() >= 3


func _weighted_order(cands: Array[Dictionary]) -> Array[Dictionary]:
	var pool := cands.duplicate()
	var out: Array[Dictionary] = []
	while not pool.is_empty():
		var total := 0.0
		for c in pool:
			total += float(c["w"])
		var r := rng.randf() * total
		var chosen := 0
		for i in pool.size():
			r -= float(pool[i]["w"])
			if r <= 0.0:
				chosen = i
				break
		out.append(pool[chosen])
		pool.remove_at(chosen)
	return out


func _pick_row(names: Array, weights: Dictionary) -> int:
	var total := 0.0
	var ws: Array[float] = []
	for n in names:
		var w: float = weights.get(str(n), 1.0)
		ws.append(w)
		total += w
	var r := rng.randf() * total
	for i in names.size():
		r -= ws[i]
		if r <= 0.0:
			return _row(str(names[i]))
	return _row(str(names[names.size() - 1]))


func _make_props() -> void:
	var plane := lib.entry("veg_plane")
	for s in streets:
		var sz: float = s["z"]
		var x: float = s["x0"] + 10.0
		while x < s["x1"]:
			var zone := zone_at(x, sz)
			var step := 26.0 if zone in [&"center", &"dense", &"historic"] else 70.0
			if zone != &"industry":
				for side in [-1.0, 1.0]:
					var p := Vector3(x + rng.randf_range(-3.0, 3.0), 0.0, sz + side * 4.6)
					var in_corridor: bool = absf(sz - float(street_view["z"])) < 0.1 and p.x > float(street_view["focus_x"]) - 80.0 \
							and p.x < float(street_view["focus_x"]) - 14.0
					if not in_corridor and not PLAZA.grow(2.0).has_point(Vector2(p.x, p.z)) and rng.randf() < 0.55:
						var sc := rng.randf_range(0.85, 1.1)
						props.append({"id": "veg_plane", "entry": plane, "pos": p, "rot": rng.randf() * TAU,
								"scale": Vector3(sc, rng.randf_range(0.9, 1.1), sc), "wall": _row("W1"),
								"roof": _row(["P2", "P3", "P4"][rng.randi() % 3]), "accent": _row("A1"), "bright": 1.0})
			x += step
		var car_step := 38.0
		x = s["x0"] + 5.0
		while x < s["x1"]:
			var zone2 := zone_at(x, sz)
			var dir := 1.0 if rng.randf() < 0.5 else -1.0
			var p2 := Vector3(x + rng.randf_range(-6.0, 6.0), 0.0, sz + dir * 2.2)
			var colors: Array = lib.entry("veh_car")["palette"]["wall_rows"]
			if not PLAZA.grow(2.0).has_point(Vector2(p2.x, p2.z)) and rng.randf() < (0.8 if zone2 != &"village" else 0.3):
				props.append({"id": "veh_car", "entry": lib.entry("veh_car"), "pos": p2,
						"rot": -PI / 2.0 * dir, "scale": Vector3.ONE,
						"wall": _row(str(colors[rng.randi() % colors.size()])), "roof": _row("R2"), "accent": _row("A1"),
						"bright": 1.0 + rng.randf_range(-0.05, 0.05)})
			x += car_step
		# yayalar yalnız merkezde (ölçek okuması)
		x = s["x0"] + 3.0
		while x < s["x1"]:
			if sqrt(x * x + sz * sz) < 190.0 and rng.randf() < 0.7:
				var side2 := 1.0 if rng.randf() < 0.5 else -1.0
				var p3 := Vector3(x, 0.0, sz + side2 * rng.randf_range(4.0, 5.4))
				if not PLAZA.grow(1.0).has_point(Vector2(p3.x, p3.z)):
					_add_human(p3)
			x += 14.0
	# meydan: yayalar + kenar ağaçları
	for i in 14:
		_add_human(Vector3(rng.randf_range(-26.0, 26.0), 0.0, rng.randf_range(-22.0, 22.0)))
	for tx in [-27.0, -13.0, 13.0, 27.0]:
		for tz in [-23.0, 23.0]:
			props.append({"id": "veg_plane", "entry": plane, "pos": Vector3(tx, 0.0, tz), "rot": rng.randf() * TAU,
					"scale": Vector3(0.95, 1.0, 0.95), "wall": _row("W1"), "roof": _row("P2"), "accent": _row("A1"),
					"bright": 1.0})


func _add_human(pos: Vector3) -> void:
	var cloth: Array = ["W2", "W5", "W6", "W7", "W9", "W3"]
	var legs: Array = ["R2", "R7", "R5", "R1"]
	var h := lib.entry("prop_human")
	props.append({"id": "prop_human", "entry": h, "pos": pos, "rot": rng.randf() * TAU,
			"scale": Vector3.ONE, "wall": _row(cloth[rng.randi() % cloth.size()]),
			"roof": _row(legs[rng.randi() % legs.size()]), "accent": _row("A1"), "bright": 1.0})
