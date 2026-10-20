class_name KitLabMetrics
extends RefCounted
## kit_lab ölçümleri (T-004 ölçüt 4): spec 3.2 çatı payı ve 3.3 tekrar/varyasyon sayaçları ile saat kulesi
## oranı.
## Girdi KitLabLayout.placements (veri); çıktı JSON'a dönüşebilir sözlük. Saf hesap — render'dan bağımsız
## (testlenir).

const FLAT_ROWS := ["R1", "R2"]
const TILE_ROWS := ["R3", "R4", "R5"]
const METAL_ROWS := ["R6", "R7"]
const WINDOW_500 := 500.0
const WINDOW_200 := 200.0
const WINDOW_100 := 100.0


## Çatı sınıfı: flat | tile | metal | other (testere dişi ve kurşun R8 = diğer, spec 3.2 tablosu).
static func roof_class(entry: Dictionary, roof_row_name: String) -> StringName:
	if str(entry["roof_type"]) == "sawtooth":
		return &"other"
	if roof_row_name in FLAT_ROWS:
		return &"flat"
	if roof_row_name in TILE_ROWS:
		return &"tile"
	if roof_row_name in METAL_ROWS:
		return &"metal"
	return &"other"


static func footprint_area(p: Dictionary) -> float:
	var fp: Array = p["entry"]["footprint_m"]
	var s: Vector3 = p["scale"]
	return float(fp[0]) * s.x * float(fp[1]) * s.z


static func _row_name(row: int) -> String:
	for r in KitMaterial.palette().get("rows", []):
		if int(r["row"]) == row:
			return str(r["name"])
	return ""


## Çatı alanı payları (yüzde): {flat, tile, metal, other}, toplam alan ve kiremit tonu dağılımı.
static func roof_shares(items: Array) -> Dictionary:
	var area := {&"flat": 0.0, &"tile": 0.0, &"metal": 0.0, &"other": 0.0}
	var tile_rows := {}
	var total := 0.0
	for p in items:
		var a := footprint_area(p)
		var rn := _row_name(int(p["roof"]))
		var cls := roof_class(p["entry"], rn)
		area[cls] += a
		total += a
		if cls == &"tile":
			tile_rows[rn] = float(tile_rows.get(rn, 0.0)) + a
	var out := {"area_m2": snappedf(total, 1.0), "count": items.size()}
	for k in area:
		out[str(k)] = snappedf(100.0 * area[k] / maxf(total, 1.0), 0.1)
	var tile_total: float = area[&"tile"]
	var tones := {}
	for rn in tile_rows:
		tones[rn] = snappedf(100.0 * float(tile_rows[rn]) / maxf(tile_total, 1.0), 0.1)
	out["tile_tones_pct_of_tile"] = tones
	out["tile_tone_count"] = tile_rows.size()
	out["r3_pct_of_tile"] = float(tones.get("R3", 0.0))
	return out


static func shares_by_zone(placements: Array) -> Dictionary:
	var by_zone := {}
	for p in placements:
		var z := str(p["zone"])
		if not by_zone.has(z):
			by_zone[z] = []
		(by_zone[z] as Array).append(p)
	var out := {}
	for z in by_zone:
		out[z] = roof_shares(by_zone[z])
	out["_all"] = roof_shares(placements)
	return out


## Kayan 500 × 500 m pencerelerde en yüksek kiremit payı (≥ min_count yapı olan pencereler).
static func max_tile_share_window(placements: Array, area: Rect2, window: float = WINDOW_500, step: float = 100.0,
		min_count: int = 25) -> Dictionary:
	var best := {"tile_pct": 0.0, "origin": Vector2.ZERO, "count": 0, "windows": 0}
	var x := area.position.x
	while x + window <= area.end.x + 0.1:
		var z := area.position.y
		while z + window <= area.end.y + 0.1:
			var r := Rect2(x, z, window, window)
			var items: Array = []
			for p in placements:
				var pos: Vector3 = p["pos"]
				if r.has_point(Vector2(pos.x, pos.z)):
					items.append(p)
			if items.size() >= min_count:
				best["windows"] += 1
				var sh := roof_shares(items)
				if float(sh["tile"]) > float(best["tile_pct"]):
					best["tile_pct"] = sh["tile"]
					best["origin"] = Vector2(x, z)
					best["count"] = items.size()
			z += step
		x += step
	return best


## Spec 3.3 sayaçları. rows: satır başına placements indeksleri (x sırasıyla).
static func variation_counters(placements: Array, rows: Array) -> Dictionary:
	var adjacent_same := 0
	var max_run := 1
	var window_bad := 0
	var windows := 0
	for row in rows:
		var run := 1
		for i in range(1, row.size()):
			var a: Dictionary = placements[row[i - 1]]
			var b: Dictionary = placements[row[i]]
			var gap := _gap_x(a, b)
			var same: bool = a["id"] == b["id"] and a["wall"] == b["wall"] and gap < 8.0
			if same:
				adjacent_same += 1
			var same3: bool = same and a["entry"]["floors"] == b["entry"]["floors"]
			run = run + 1 if same3 else 1
			max_run = maxi(max_run, run)
		for i in range(0, row.size() - 8):
			var ids := {}
			var walls := {}
			for k in 9:
				var q: Dictionary = placements[row[i + k]]
				ids[q["id"]] = true
				walls[q["wall"]] = true
			windows += 1
			if ids.size() < 3 or walls.size() < 3:
				window_bad += 1
	return {"adjacent_same_mesh_wall": adjacent_same, "max_identical_run": max_run, "windows_9": windows,
			"windows_9_below_3_variety": window_bad}


## İki ardışık yapı arasındaki x boşluğu (m): sokak/çapraz sokak boşluğu olanlar komşu sayılmaz.
static func _gap_x(a: Dictionary, b: Dictionary) -> float:
	var aw: float = float(a["entry"]["footprint_m"][0]) * (a["scale"] as Vector3).x
	var bw: float = float(b["entry"]["footprint_m"][0]) * (b["scale"] as Vector3).x
	return ((b["pos"] as Vector3).x - bw * 0.5) - ((a["pos"] as Vector3).x + aw * 0.5)


## Orta yoğun bölgelerde (center/dense) 100 × 100 m pencerede kat sayısı std ve 200 × 200 m'de benzersiz
## (mesh, kat, duvar) oranı.
static func floors_and_unique(placements: Array, area: Rect2) -> Dictionary:
	var min_std := 99.0
	var windows_floors := 0
	var below_floors := 0
	var min_unique := 99.0
	var windows_unique := 0
	var below_unique := 0
	var failing: Array = []
	var x := area.position.x
	while x + WINDOW_100 <= area.end.x + 0.1:
		var z := area.position.y
		while z + WINDOW_100 <= area.end.y + 0.1:
			var r := Rect2(x, z, WINDOW_100, WINDOW_100)
			var floors: Array[float] = []
			for p in placements:
				var pos: Vector3 = p["pos"]
				if r.has_point(Vector2(pos.x, pos.z)) and p["zone"] in [&"center", &"dense"]:
					if str(p["entry"]["family"]) in ["res_mid", "res_old", "res_late"]:
						floors.append(float(p["entry"]["floors"]))
			if floors.size() >= 10:
				var mean := 0.0
				for f in floors:
					mean += f
				mean /= floors.size()
				var v := 0.0
				for f in floors:
					v += (f - mean) * (f - mean)
				var sd := sqrt(v / floors.size())
				windows_floors += 1
				min_std = minf(min_std, sd)
				if sd < 1.0:
					below_floors += 1
			z += WINDOW_100
		x += WINDOW_100
	x = area.position.x
	while x + WINDOW_200 <= area.end.x + 0.1:
		var z2 := area.position.y
		while z2 + WINDOW_200 <= area.end.y + 0.1:
			var r2 := Rect2(x, z2, WINDOW_200, WINDOW_200)
			var combos := {}
			var n := 0
			for p in placements:
				var pos2: Vector3 = p["pos"]
				if r2.has_point(Vector2(pos2.x, pos2.z)):
					n += 1
					combos["%s/%s/%s" % [p["id"], p["entry"]["floors"], p["wall"]]] = true
			if n >= 10:
				var ratio := combos.size() / float(n)
				windows_unique += 1
				min_unique = minf(min_unique, ratio)
				if ratio < 0.6:
					below_unique += 1
					failing.append({"origin": "%d,%d" % [int(x), int(z2)], "count": n, "ratio": snappedf(ratio, 0.01),
							"distinct_combos": combos.size()})
			z2 += WINDOW_200
		x += WINDOW_200
	return {"windows_floor_std": windows_floors, "min_floor_std": snappedf(min_std, 0.01),
			"windows_floor_std_below_1": below_floors, "windows_unique": windows_unique,
			"min_unique_ratio": snappedf(min_unique, 0.01), "windows_unique_below_60pct": below_unique,
			"failing_unique_windows": failing}


## Saat kulesi oranı (spec 4): H_s = 150 m çevresindeki en yüksek çerçeve yapının parapet üstü; 1,3 ≤ 23 /
## H_s ≤ 1,8.
static func tower_ratio(placements: Array, tower_height: float, radius: float = 150.0) -> Dictionary:
	var hs := 0.0
	var who := ""
	var n := 0
	for p in placements:
		var pos: Vector3 = p["pos"]
		if Vector2(pos.x, pos.z).length() <= radius:
			n += 1
			var top := (float(p["entry"]["eave_height_m"]) + 0.9) * (p["scale"] as Vector3).y
			if top > hs:
				hs = top
				who = str(p["id"])
	return {"tower_height_m": snappedf(tower_height, 0.01), "frame_count": n, "h_s_m": snappedf(hs, 0.01),
			"tallest_frame": who, "ratio": snappedf(tower_height / maxf(hs, 0.01), 0.01),
			"ok": tower_height / maxf(hs, 0.01) >= 1.3 and tower_height / maxf(hs, 0.01) <= 1.8}


## Tüm ölçümler tek sözlükte (kit_lab, rapor betiği ve test paylaşır).
static func full_report(lib: KitLibrary, layout: KitLabLayout) -> Dictionary:
	var pl := layout.placements
	var area := KitLabLayout.AREA
	var tower_h: float = float(lib.entry("bld_lmk_clocktower")["total_height_m"]) * (layout.tower["scale"] as Vector3).y
	var counts := {}
	for p in pl:
		var fam := str(p["entry"]["family"])
		counts[fam] = int(counts.get(fam, 0)) + 1
	return {
		"building_count": pl.size(), "prop_count": layout.props.size(), "families": counts,
		"roof_shares_by_zone": shares_by_zone(pl),
		"tile_500m_window": max_tile_share_window(pl, area),
		"variation_3_3": variation_counters(pl, layout.rows),
		"floors_unique": floors_and_unique(pl, area),
		"tower": tower_ratio(pl, tower_h),
	}
