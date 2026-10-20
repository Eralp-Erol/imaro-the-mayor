class_name DevBuildingSource
extends RefCounted
## STAND-IN yapı kaynağı (DEV; T-012). Gerçek T0 yerleşimi `T0Settlement.generate(world, net, manifest, seed, control)`
## (T-005, world hattı) aynı `BuildingColumns` sözleşmesini üretir; bu sınıf onun yerini yalnız o gelene kadar tutar ve
## render'ın ölçeğini (on binlerce yapı, gerçek `WorldNetwork` parselleri) göstermek içindir. Gerçeğe geçişte değişen
## TEK yer çağırandır (ör. world_preview): `BuildingView.set_columns(<kaynak>)`.
##
## Algoritma = `scenes/dev/kit_lab_layout.gd` (art hattı referansı) kuralları, parsel başına: bölgeye göre aile
## ağırlıkları, komşu aynı (modül + duvar) olmaması, 8'li pencerede >= 3 modül ve >= 3 duvar rengi, çatı/duvar satırı
## ağırlıkları (kiremit payı kuralı), yön = cephe yolu. Yerleşim parsel POLİGONU içindedir (cephe orta noktası +
## cephe normali); alan kullanımı ağ parsel şablonundan (`fabric`) ve hub uzaklığından türer. Koordinat gömülü değil.
##
## Bu bir tasarım KARARI değildir (F05-C: tekil yapı/konum onaylı değil); VIS-04 için yoğunluk ve çeşitlilik gösterir.
## CAN-03: oyuncu bina koymaz; bu, sim'in başlangıç stoğunun yerine geçen görsel stand-in'dir ve sim'e yazmaz.

const ZONE_CENTER := &"center"
const ZONE_DENSE := &"dense"
const ZONE_HISTORIC := &"historic"
const ZONE_VILLAGE := &"village"
const ZONE_INDUSTRY := &"industry"

## Bölge -> [aile, ağırlık] (kit_lab_layout.ZONE_FAMILY_WEIGHTS ile aynı).
const ZONE_FAMILY_WEIGHTS := {
	&"center": [["res_mid", 0.38], ["res_old", 0.25], ["res_late", 0.23], ["civ_hall", 0.02], ["res_house", 0.05]],
	&"dense": [["res_mid", 0.40], ["res_late", 0.27], ["res_old", 0.19], ["civ_hall", 0.015], ["res_house", 0.025]],
	&"historic": [["res_old", 0.66], ["res_mid", 0.05], ["res_house", 0.29]],
	&"village": [["res_house", 0.60], ["res_old", 0.40]],
	&"industry": [["ind_shed", 0.50], ["ind_heritage", 0.16], ["res_late", 0.12], ["res_mid", 0.16],
			["res_house", 0.06]],
}
const ID_WEIGHT := {"bld_ind_shed_b": 0.3, "bld_ind_heritage_b": 0.35, "bld_civ_hall_b": 0.7, "bld_res_old_c": 0.8,
		"bld_res_old_c_gf": 0.8}
const ROOF_ROW_WEIGHTS := {"R1": 0.68, "R2": 0.32, "R3": 0.30, "R4": 0.42, "R5": 0.28, "R6": 0.50, "R7": 0.50,
		"R8": 1.0}
const HOUSE_ROOF_ROW_WEIGHTS := {"R3": 0.30, "R4": 0.42, "R5": 0.28, "R6": 0.17}
const WALL_ROW_WEIGHTS := {"W1": 0.28, "W2": 0.22, "W3": 0.09, "W4": 0.05, "W5": 0.12, "W6": 0.06, "W7": 0.06,
		"W8": 0.10, "W9": 0.12, "W10": 1.0, "W11": 1.0, "W12": 0.5, "W13": 0.5}
const ATTACHED_FAMILIES: Array[String] = ["res_old", "res_mid", "res_late", "com_bazaar", "off_mid"]
const MIN_FILL := 0.38
const WINDOW := 8
## Hub'a uzaklık eşikleri (m): merkez/tarihî çekirdek yarıçapı; kentsel dokunun dış kenarında (fabric başına) köy
## ağırlığına geçiş (kentsel doku T-011 şablonlarıyla hub'dan ~1,5-2 km uzanır).
const CENTER_RADIUS_M := 700.0
const HISTORIC_RADIUS_M := 500.0
const VILLAGE_DISTANCE_M := {&"core": 1900.0, &"compact": 1600.0, &"mixed": 1600.0}
const SETBACK_ATTACHED_M := 0.5
const SETBACK_HOUSE_M := 3.5
const SETBACK_INDUSTRY_M := 5.0
const YARD_GAP_M := 7.0
const REAR_GAP_M := 3.0
const REAR_CHANCE := 0.7
const FIT_TOLERANCE := 0.96
const TOWER_ID := "bld_lmk_clocktower"
const TOWER_REGION := &"D1"
const ERA_BY_LABEL := {"old": 0, "mid": 1, "late": 2, "new": 3}


## Tüm `WorldNetwork` parsellerinden yapı stoğu. `manifest` = `KitLibrary.manifest` (modül sırası = module_idx).
static func generate(world: WorldData, net: WorldNetwork, manifest: Dictionary, seed_value: int) -> BuildingColumns:
	var cols := BuildingColumns.new()
	var table := _module_table(manifest)
	var zone_cands := _zone_candidates(table)
	var tower_pid := _tower_parcel(net, table)
	var block_ids: Array = net.blocks.keys()
	block_ids.sort()
	var rng := RandomNumberGenerator.new()
	for bid: int in block_ids:
		var block: WorldBlock = net.blocks[bid]
		if block.kind != WorldBlock.KIND_PARCELIZED:
			continue
		rng.seed = _block_seed(seed_value, bid)
		var history: Array[Dictionary] = []
		var parcel_ids := block.parcel_ids.duplicate()
		parcel_ids.sort()
		for pid in parcel_ids:
			var parcel := net.parcels.get(pid) as WorldParcel
			if parcel == null or parcel.frontage_edge < 0 or parcel.front_length < 5.0:
				continue
			var frame := _frame_of(parcel)
			if frame.is_empty():
				continue
			if pid == tower_pid:
				_place_tower(cols, world, parcel, frame, table)
				continue
			var zone := _zone_of(parcel, net)
			match parcel.fabric:
				&"industrial":
					_fill_industrial(cols, world, parcel, frame, zone_cands, rng)
				&"rural":
					_fill_rural(cols, world, parcel, frame, zone_cands, rng)
				_:
					_fill_urban(cols, world, parcel, frame, zone_cands[zone], rng, history)
	return cols


# --- tablolar ------------------------------------------------------------------------------------------------

static func _module_table(manifest: Dictionary) -> Array[Dictionary]:
	var table: Array[Dictionary] = []
	var modules: Array = manifest.get("modules", [])
	for n in modules.size():
		var e: Dictionary = modules[n]
		var pal: Dictionary = e.get("palette", {})
		var fp: Array = e.get("footprint_m", [0.0, 0.0])
		table.append({
			"idx": n, "id": str(e["id"]), "kind": str(e.get("kind", "")), "family": str(e.get("family", "")),
			"w": float(fp[0]), "d": float(fp[1]), "floors": int(e.get("floors", 0)), "gf": bool(e.get("gf", false)),
			"era": int(ERA_BY_LABEL.get(str(e.get("era", "")), BuildingColumns.ERA_NONE)),
			"wall_rows": _row_names(pal.get("wall_rows", [])), "roof_rows": _row_names(pal.get("roof_rows", [])),
			"accent_rows": _row_names(pal.get("accent_rows", [])),
		})
	return table


static func _row_names(names: Array) -> Array[String]:
	var out: Array[String] = []
	for n in names:
		out.append(str(n))
	return out


## Bölge -> aday listesi ({cand, w}); yalnız `building` türü, landmark değil.
static func _zone_candidates(table: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for zone: StringName in ZONE_FAMILY_WEIGHTS:
		var list: Array[Dictionary] = []
		for fw: Array in ZONE_FAMILY_WEIGHTS[zone]:
			var fam: String = fw[0]
			var members: Array[Dictionary] = []
			for c in table:
				if c["kind"] == "building" and c["family"] == fam:
					members.append(c)
			for c in members:
				var w := float(fw[1]) / float(members.size()) * float(ID_WEIGHT.get(c["id"], 1.0))
				if c["gf"]:
					w *= 0.8 if zone != ZONE_VILLAGE else 0.3
				list.append({"c": c, "w": w})
		out[zone] = list
	return out


static func _block_seed(seed_value: int, block_id: int) -> int:
	return (seed_value * 1000003) ^ (block_id * 7919 + 104729)


# --- parsel çerçevesi ------------------------------------------------------------------------------------

## Parselin yerel çerçevesi: n = cepheye bakan birim vektör (dünya xz), t = cephe teğeti, front = cephe orta noktası,
## depth = cepheden arka kenara derinlik, u0 = centroid'in cephe boyunca kayması.
static func _frame_of(parcel: WorldParcel) -> Dictionary:
	var to_front := parcel.front_mid - parcel.centroid
	if to_front.length() < 0.5:
		return {}
	var n := to_front.normalized()
	var t := Vector2(-n.y, n.x)
	var front_proj := parcel.front_mid.dot(n)
	var back_proj := front_proj
	for p in parcel.outline:
		back_proj = minf(back_proj, p.dot(n))
	return {"n": n, "t": t, "front": parcel.front_mid, "depth": front_proj - back_proj, "u0":
			(parcel.centroid - parcel.front_mid).dot(t), "yaw": atan2(n.x, n.y)}


static func _zone_of(parcel: WorldParcel, net: WorldNetwork) -> StringName:
	match parcel.fabric:
		&"industrial":
			return ZONE_INDUSTRY
		&"rural":
			return ZONE_VILLAGE
	var dist := 0.0   # hub bilgisi yoksa merkezî say (sentetik ağlar)
	var hub: Variant = net.hubs.get(parcel.region_code)
	if hub != null:
		dist = parcel.centroid.distance_to(net.node_pos(int(hub)))
	if dist > float(VILLAGE_DISTANCE_M.get(parcel.fabric, 1600.0)):
		return ZONE_VILLAGE
	if parcel.fabric == &"core" and dist < CENTER_RADIUS_M:
		return ZONE_CENTER
	if parcel.fabric == &"compact" and dist < HISTORIC_RADIUS_M:
		return ZONE_HISTORIC
	return ZONE_DENSE


static func _tower_parcel(net: WorldNetwork, table: Array[Dictionary]) -> int:
	var has_tower := false
	for c in table:
		if c["id"] == TOWER_ID:
			has_tower = true
	var hub: Variant = net.hubs.get(TOWER_REGION)
	if not has_tower or hub == null:
		return -1
	var at := net.node_pos(int(hub))
	var best := -1
	var best_d := INF
	var ids: Array = net.parcels.keys()
	ids.sort()
	for pid: int in ids:
		var p: WorldParcel = net.parcels[pid]
		if p.region_code != TOWER_REGION or p.fabric != &"core" or p.frontage_edge < 0:
			continue
		var d := p.centroid.distance_to(at)
		if d < best_d:
			best_d = d
			best = pid
	return best


# --- yerleşim ----------------------------------------------------------------------------------------------

static func _place_tower(cols: BuildingColumns, world: WorldData, parcel: WorldParcel, frame: Dictionary,
		table: Array[Dictionary]) -> void:
	for c in table:
		if c["id"] != TOWER_ID:
			continue
		var pos: Vector2 = parcel.centroid
		if _fits(world, parcel, pos, float(frame["yaw"]), float(c["w"]), float(c["d"])):
			_add(cols, parcel, c, pos, float(frame["yaw"]), _row("W11"), _row("R8"), _row("A1"), 128,
					BuildingColumns.FLAG_LANDMARK | BuildingColumns.FLAG_HERITAGE)
		return


static func _fill_urban(cols: BuildingColumns, world: WorldData, parcel: WorldParcel, frame: Dictionary,
		cands: Array, rng: RandomNumberGenerator, history: Array[Dictionary]) -> void:
	var depth: float = frame["depth"]
	var front_len := parcel.front_length
	var fitting: Array[Dictionary] = []
	for entry: Dictionary in cands:
		var c: Dictionary = entry["c"]
		var attached: bool = (c["family"] as String) in ATTACHED_FAMILIES
		var setback := SETBACK_ATTACHED_M if attached else SETBACK_HOUSE_M
		if float(c["d"]) + setback > depth * 1.02 or float(c["w"]) > front_len * 1.02:
			continue
		var fill := float(c["w"]) / front_len
		if attached and fill < MIN_FILL:
			continue
		var fill_d := minf(float(c["d"]) / depth, 1.0)
		var weight := float(entry["w"]) * ((pow(fill, 2.0) + 0.15) * (0.35 + fill_d) if attached else 1.0)
		fitting.append({"c": c, "w": weight, "setback": setback})
	if fitting.is_empty():
		return
	var pool := fitting.duplicate()
	var prev: Dictionary = history.back() if not history.is_empty() else {}
	for attempt in 8:
		if pool.is_empty():
			return
		var pick_n := _weighted_index(pool, rng)
		var pick: Dictionary = pool[pick_n]
		var c: Dictionary = pick["c"]
		var wall := _pick_row(c["wall_rows"], WALL_ROW_WEIGHTS, rng)
		var strict := attempt < 5
		if strict:
			if not prev.is_empty() and (prev["idx"] == c["idx"] or prev["wall"] == wall):
				pool.remove_at(pick_n)
				continue
			if not _window_ok(history, int(c["idx"]), wall):
				pool.remove_at(pick_n)
				continue
		var pos := _front_anchored(frame, float(pick["setback"]), float(c["d"]))
		if not _fits(world, parcel, pos, float(frame["yaw"]), float(c["w"]), float(c["d"])):
			pool.remove_at(pick_n)
			continue
		var roof := _pick_row(c["roof_rows"], HOUSE_ROOF_ROW_WEIGHTS if c["family"] == "res_house" else
				ROOF_ROW_WEIGHTS, rng)
		var accent := _pick_row(c["accent_rows"], {}, rng)
		_add(cols, parcel, c, pos, float(frame["yaw"]), wall, roof, accent, rng.randi_range(0, 255), 0)
		history.append({"idx": c["idx"], "wall": wall})
		if history.size() > WINDOW * 2:
			history.remove_at(0)
		_fill_rear(cols, world, parcel, frame, fitting, float(pick["setback"]) + float(c["d"]) + REAR_GAP_M, rng)
		return
	# kurallar sıkı kaldı: bu parsel boş bırakılır (boşluk, dolgu uydurmaktan iyidir)


## Arka bina (avlu/arka cephe): parselin cepheden uzak kalan derinliğine, cephe binasının arkasına küçük bir yapı
## (yoğunluk; "tek sıra maket" etkisini kırar). Aday kümesi cephe adaylarından; derinlik ve genişlik uyanlardan seçilir.
static func _fill_rear(cols: BuildingColumns, world: WorldData, parcel: WorldParcel, frame: Dictionary,
		fitting: Array, used: float, rng: RandomNumberGenerator) -> void:
	var depth: float = frame["depth"]
	var room: Array[Dictionary] = []
	for entry: Dictionary in fitting:
		var c: Dictionary = entry["c"]
		if float(c["d"]) + used <= depth - 0.5 and float(c["w"]) <= parcel.front_length * 0.95 \
				and float(c["floors"]) <= 4.0 and not c["gf"]:
			room.append(entry)
	if room.is_empty() or rng.randf() > REAR_CHANCE:
		return
	var pick: Dictionary = room[_weighted_index(room, rng)]
	var c: Dictionary = pick["c"]
	var pos := _front_anchored(frame, used, float(c["d"]))
	if _fits(world, parcel, pos, float(frame["yaw"]), float(c["w"]), float(c["d"])):
		var roof := _pick_row(c["roof_rows"], HOUSE_ROOF_ROW_WEIGHTS if c["family"] == "res_house" else
				ROOF_ROW_WEIGHTS, rng)
		_add(cols, parcel, c, pos, float(frame["yaw"]), _pick_row(c["wall_rows"], WALL_ROW_WEIGHTS, rng), roof,
				_pick_row(c["accent_rows"], {}, rng), rng.randi_range(0, 255), 0)


## Sanayi parseli: avlu içinde 1-3 hacim, cepheden arkaya sıralı (spec §3.1 I: "3 konteyner" etkisi değil, avlu).
static func _fill_industrial(cols: BuildingColumns, world: WorldData, parcel: WorldParcel, frame: Dictionary,
		zone_cands: Dictionary, rng: RandomNumberGenerator) -> void:
	var cands: Array = zone_cands[ZONE_INDUSTRY]
	var depth: float = frame["depth"]
	var used := SETBACK_INDUSTRY_M
	for _slot in 3:
		var fitting: Array[Dictionary] = []
		for entry: Dictionary in cands:
			var cand: Dictionary = entry["c"]
			if not (cand["family"] in ["ind_shed", "ind_heritage"]):
				continue
			if float(cand["w"]) <= parcel.front_length - 4.0 and used + float(cand["d"]) <= depth - 2.0:
				fitting.append({"c": cand, "w": float(entry["w"])})
		if fitting.is_empty():
			break
		var c: Dictionary = fitting[_weighted_index(fitting, rng)]["c"]
		var pos := _front_anchored(frame, used, float(c["d"]))
		if _fits(world, parcel, pos, float(frame["yaw"]), float(c["w"]), float(c["d"])):
			var wall := _pick_row(c["wall_rows"], WALL_ROW_WEIGHTS, rng)
			var roof := _pick_row(c["roof_rows"], ROOF_ROW_WEIGHTS, rng)
			var flags := BuildingColumns.FLAG_INDUSTRY
			if parcel.region_code == &"D3":
				flags |= BuildingColumns.FLAG_PORT_YARD
			_add(cols, parcel, c, pos, float(frame["yaw"]), wall, roof, _pick_row(c["accent_rows"], {}, rng),
					rng.randi_range(0, 255), flags)
		used += float(c["d"]) + YARD_GAP_M


## Kırsal büyük parsel: cephe boyunca 1-3 müstakil ev (tarım boş leke olmasın, VIS-04).
static func _fill_rural(cols: BuildingColumns, world: WorldData, parcel: WorldParcel, frame: Dictionary,
		zone_cands: Dictionary, rng: RandomNumberGenerator) -> void:
	var cands: Array = zone_cands[ZONE_VILLAGE]
	var count := rng.randi_range(1, 3)
	var t: Vector2 = frame["t"]
	var n: Vector2 = frame["n"]
	for k in count:
		var entry: Dictionary = cands[_weighted_index(cands, rng)]
		var c: Dictionary = entry["c"]
		var u := float(frame["u0"]) + (float(k) - float(count - 1) * 0.5) * parcel.front_length / float(count + 1) \
				+ rng.randf_range(-12.0, 12.0)
		var setback := rng.randf_range(12.0, 45.0)
		var pos: Vector2 = (frame["front"] as Vector2) + t * u - n * (setback + float(c["d"]) * 0.5)
		if _fits(world, parcel, pos, float(frame["yaw"]), float(c["w"]), float(c["d"])):
			var roof := _pick_row(c["roof_rows"], HOUSE_ROOF_ROW_WEIGHTS if c["family"] == "res_house" else
					ROOF_ROW_WEIGHTS, rng)
			_add(cols, parcel, c, pos, float(frame["yaw"]), _pick_row(c["wall_rows"], WALL_ROW_WEIGHTS, rng), roof,
					_pick_row(c["accent_rows"], {}, rng), rng.randi_range(0, 255), 0)


## Cephe yüzü `setback` içeride, parsel cephe hattının ortasında; merkez = yüz - n * d/2.
static func _front_anchored(frame: Dictionary, setback: float, d: float) -> Vector2:
	var t: Vector2 = frame["t"]
	var n: Vector2 = frame["n"]
	return (frame["front"] as Vector2) + t * float(frame["u0"]) - n * (setback + d * 0.5)


## Yönlü dikdörtgen parselin içinde ve karada mı (köşeler `FIT_TOLERANCE` ile içe çekilmiş).
static func _fits(world: WorldData, parcel: WorldParcel, pos: Vector2, yaw: float, w: float, d: float) -> bool:
	var c := cos(yaw)
	var s := sin(yaw)
	for p in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var lx: float = p.x * w * FIT_TOLERANCE
		var lz: float = p.y * d * FIT_TOLERANCE
		var corner := Vector2(pos.x + lx * c + lz * s, pos.y - lx * s + lz * c)
		if not Geometry2D.is_point_in_polygon(corner, parcel.outline):
			return false
		if world.is_water(corner.x, corner.y):
			return false
	return true


static func _add(cols: BuildingColumns, parcel: WorldParcel, c: Dictionary, pos: Vector2, yaw: float, wall: int,
		roof: int, accent: int, bright: int, extra_flags: int) -> void:
	var flags := extra_flags
	if c["gf"]:
		flags |= BuildingColumns.FLAG_GROUND_SHOP
	var family: String = c["family"]
	if family.begins_with("ind_"):
		flags |= BuildingColumns.FLAG_INDUSTRY
	if family == "ind_heritage":
		flags |= BuildingColumns.FLAG_HERITAGE
	if family.begins_with("civ_"):
		flags |= BuildingColumns.FLAG_CIVIC
	cols.add(parcel.id, int(c["idx"]), pos.x, pos.y, yaw, int(c["floors"]), wall, roof, accent, bright, flags,
			int(c["era"]))


static func _window_ok(history: Array[Dictionary], idx: int, wall: int) -> bool:
	if history.size() < WINDOW:
		return true
	var ids := {idx: true}
	var walls := {wall: true}
	for k in range(history.size() - WINDOW, history.size()):
		ids[history[k]["idx"]] = true
		walls[history[k]["wall"]] = true
	return ids.size() >= 3 and walls.size() >= 3


static func _weighted_index(list: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for e: Dictionary in list:
		total += float(e["w"])
	var r := rng.randf() * total
	for n in list.size():
		r -= float((list[n] as Dictionary)["w"])
		if r <= 0.0:
			return n
	return list.size() - 1


static func _pick_row(names: Array, weights: Dictionary, rng: RandomNumberGenerator) -> int:
	if names.is_empty():
		return 0
	var total := 0.0
	for n in names:
		total += float(weights.get(str(n), 1.0))
	var r := rng.randf() * total
	for n in names:
		r -= float(weights.get(str(n), 1.0))
		if r <= 0.0:
			return _row(str(n))
	return _row(str(names[names.size() - 1]))


static func _row(row_name: String) -> int:
	var r := KitMaterial.row_index(row_name)
	return r if r >= 0 else 0
