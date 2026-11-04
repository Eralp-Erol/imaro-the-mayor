class_name ParcelExpropriation
extends RefCounted
## T-042b · Kamulaştırmanın EKONOMİ tarafı (D-011, ADR-0005 Ek F): yolun aldığı parsel BÜTÜNÜYLE `STAGE_TAKEN` olur.
## Sim parsel kümesi ve kimlikleri DEĞİŞMEZ (seçenek A); bina yıkılır (bölge yapılı birimi düşer), devam eden proje
## iptal
## olur (boru hattından çıkar), hane kaderi VERİ bayrağıdır (Q-017: çalışma değeri `return_to_latent` = bölge talebine
## döner, `leave_region` = bölgeden ayrılır). Geri alma alınan satırın anlık görüntüsünü geri koyar.
##
## SAF ve durumsuz: `plan` durumu DEĞİŞTİRMEZ (önizleme ve tick AYNI hesabı kullanır), `apply`/`restore` yalnız ekonomi
## sütunlarını yazar. Rastgelelik yok; parsel kimliği artan sırada işlenir. Para yok (bedel T-014, Q-003).
##
## `cols`: `EconomySystem.static_columns()` (statik, kaynaktan türeyen sütunlar: region_of, center_x/z (cm), codes).
## Kimlik/indeks: ekonomi durumundaki `parcel_ids` (artan) = kaynak sırası.

const FATE_RETURN := &"return_to_latent"
const FATE_LEAVE := &"leave_region"
const FATES: Array[StringName] = [FATE_RETURN, FATE_LEAVE]


## Alma planı. Dönüş: {ok (durum hazır ve bilinmeyen yok), ready, unknown (bilinmeyen ya da ZATEN alınmış parsel
## sayısı),
## summary (ExpropriationSummary şeması), rows [{id, i, r}] artan kimlik, latent_removed {kod: hane} (yalnız
## leave_region), displaced {kod: yerinden edilen hane}, fate}. Durumu değiştirmez.
static func plan(state: GameState, cols: Dictionary, ids: PackedInt64Array, fate: StringName) -> Dictionary:
	var out := {"ok": false, "ready": false, "unknown": 0, "rows": [], "latent_removed": {}, "displaced": {},
		"fate": fate,
		"summary": {"parcel_ids": PackedInt64Array(), "built_parcels": 0, "project_parcels": 0, "res_units": 0,
			"com_units": 0, "households": 0, "regions": {}, "nearby_households": 0, "nearby_parcels": 0}}
	var d := EconomyState.data(state)
	if d.is_empty():
		return out
	out["ready"] = true
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var region_of: PackedInt32Array = cols["region_of"]
	var summary: Dictionary = out["summary"]
	var removed_res := {}  # bölge indeksi -> yıkılan YAPILI konut birimi
	var taken_ids := PackedInt64Array()
	for id in ExpropriationSummary.sorted_ids({"parcel_ids": ids}):
		var i := EconomyState.index_of(d, id)
		if i < 0 or stage[i] == EconomyState.STAGE_TAKEN:
			out["unknown"] += 1
			continue
		var r := region_of[i]
		(out["rows"] as Array).append({"id": id, "i": i, "r": r})
		taken_ids.append(id)
		var code := codes[r]
		(summary["regions"] as Dictionary)[code] = int((summary["regions"] as Dictionary).get(code, 0)) + 1
		var units := units_col[i]
		match stage[i]:
			EconomyState.STAGE_VACANT:
				continue
			EconomyState.STAGE_BUILT:
				summary["built_parcels"] += 1
				if use_col[i] == EconomyConfig.USE_RESIDENTIAL:
					removed_res[r] = int(removed_res.get(r, 0)) + units
			_:
				summary["project_parcels"] += 1
		if use_col[i] == EconomyConfig.USE_RESIDENTIAL:
			summary["res_units"] += units
		else:
			summary["com_units"] += units
	summary["parcel_ids"] = taken_ids
	var removed_regions: Array = removed_res.keys()
	removed_regions.sort()
	# hane = bölgenin barınan hane sayısındaki düşüş (barınan = min(bekleyen, yapılı konut))
	for r: int in removed_regions:
		var latent: int = regions["latent_hh"][r]
		var res: int = regions["res_built"][r]
		var displaced := mini(latent, res) - mini(latent, maxi(res - int(removed_res[r]), 0))
		summary["households"] += displaced
		if displaced > 0:
			(out["displaced"] as Dictionary)[codes[r]] = displaced  # tepki defteri bölge başınadır
		if fate == FATE_LEAVE and displaced > 0:
			(out["latent_removed"] as Dictionary)[codes[r]] = displaced
	out["ok"] = int(out["unknown"]) == 0
	return out


## Planı ekonomi sütunlarına yazar; alınan satırların anlık görüntülerini (artan kimlik) döndürür. `plan["ok"]` olmalı.
static func apply(state: GameState, plan_data: Dictionary) -> Array:
	var snapshots: Array = []
	var d := EconomyState.data(state)
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var days_left: PackedInt32Array = d["days_left"]
	var reason_col: PackedInt64Array = d["reason_id"]
	var last_code: PackedByteArray = d["last_code"]
	var last_tick: PackedInt32Array = d["last_reason_tick"]
	var next_review: PackedInt32Array = d["next_review"]
	var active: Dictionary = d["active"]
	for row: Dictionary in plan_data["rows"]:
		var i: int = row["i"]
		var r: int = row["r"]
		snapshots.append({"id": row["id"], "region": codes[r], "stage": stage[i], "use": use_col[i],
			"units": units_col[i], "owner_id": owner_col[i], "days_left": days_left[i], "reason_id": reason_col[i],
			"last_code": last_code[i], "last_reason_tick": last_tick[i], "next_review": next_review[i],
			"active": active.has(i)})
		_move_units(regions, r, stage[i], use_col[i], units_col[i], -1)
		stage[i] = EconomyState.STAGE_TAKEN
		use_col[i] = EconomyConfig.USE_NONE
		units_col[i] = 0
		owner_col[i] = 0
		days_left[i] = 0
		last_code[i] = EconomyState.CODE_NONE  # taşınmış karar özeti görünmez (alınmış parselde karar yok)
		last_tick[i] = -1
		next_review[i] = 0
		for key in ["active", "attention", "attention_cmd", "priority", "priority_cmd"]:
			if d.has(key):
				(d[key] as Dictionary).erase(i)
	var removed: Dictionary = plan_data["latent_removed"]
	var latent: PackedInt64Array = regions["latent_hh"]
	for code: String in removed:
		latent[codes.find(code)] -= int(removed[code])
	return snapshots


## Geri alma: `data` = {snapshots, latent_removed} (iş kaydındaki `expropriation`). Parsel hâlâ `taken` değilse atlanır
## (savunma). Aktif proje girişi geri konur; tek seferlik dikkat/öncelik girişleri geri gelmez (periyodik tarama
## parsele yine bakar).
static func restore(state: GameState, data: Dictionary) -> void:
	var d := EconomyState.data(state)
	if d.is_empty():
		return
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var days_left: PackedInt32Array = d["days_left"]
	var reason_col: PackedInt64Array = d["reason_id"]
	var last_code: PackedByteArray = d["last_code"]
	var last_tick: PackedInt32Array = d["last_reason_tick"]
	var next_review: PackedInt32Array = d["next_review"]
	var active: Dictionary = d["active"]
	for snap: Dictionary in data["snapshots"]:
		var i := EconomyState.index_of(d, int(snap["id"]))
		if i < 0 or stage[i] != EconomyState.STAGE_TAKEN:
			continue
		stage[i] = int(snap["stage"])
		use_col[i] = int(snap["use"])
		units_col[i] = int(snap["units"])
		owner_col[i] = int(snap["owner_id"])
		days_left[i] = int(snap["days_left"])
		reason_col[i] = int(snap["reason_id"])
		last_code[i] = int(snap["last_code"])
		last_tick[i] = int(snap["last_reason_tick"])
		next_review[i] = int(snap["next_review"])
		if bool(snap["active"]):
			active[i] = true
		_move_units(regions, codes.find(String(snap["region"])), int(snap["stage"]), int(snap["use"]),
			int(snap["units"]), 1)
	var removed: Dictionary = data["latent_removed"]
	var latent: PackedInt64Array = regions["latent_hh"]
	for code: String in removed:
		latent[codes.find(code)] += int(removed[code])


## Yakınlık: alınMAyan yapılı konut parsellerinden yolun `radius_m` metre içinde olanlar. `pts`: [[x, z]...] cm.
## Hane = parselin birimi x bölgenin barınan oranı. Mesafe ağırlığı = (R - d) / R, binde (pm). Dönüş: {parcels,
## households
## (ham), by_region {kod: Σ hane x ağırlık_pm}}. Durumu değiştirmez; O(parsel).
static func nearby(state: GameState, cols: Dictionary, taken_ids: PackedInt64Array, pts: Array,
		radius_m: int) -> Dictionary:
	var out := {"parcels": 0, "households": 0, "by_region": {}}
	var d := EconomyState.data(state)
	if d.is_empty() or radius_m <= 0 or pts.size() < 2:
		return out
	var radius_cm := radius_m * 100
	var radius2 := radius_cm * radius_cm
	var min_x: int = pts[0][0]
	var max_x := min_x
	var min_z: int = pts[0][1]
	var max_z := min_z
	for p: Array in pts:
		min_x = mini(min_x, p[0])
		max_x = maxi(max_x, p[0])
		min_z = mini(min_z, p[1])
		max_z = maxi(max_z, p[1])
	min_x -= radius_cm
	max_x += radius_cm
	min_z -= radius_cm
	max_z += radius_cm
	var taken := {}
	for id in taken_ids:
		taken[EconomyState.index_of(d, id)] = true
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var region_of: PackedInt32Array = cols["region_of"]
	var cx: PackedInt64Array = cols["center_x"]
	var cz: PackedInt64Array = cols["center_z"]
	for i in stage.size():  # ucuz elemeler önce (20 bin parselde çağrı başına ~ms): aşama, kutu, sonra alınan kümesi
		if stage[i] != EconomyState.STAGE_BUILT or use_col[i] != EconomyConfig.USE_RESIDENTIAL:
			continue
		if cx[i] < min_x or cx[i] > max_x or cz[i] < min_z or cz[i] > max_z or taken.has(i):
			continue
		var dist2 := PriorityReview.dist2_to_polyline(cx[i], cz[i], pts)
		if dist2 > radius2:
			continue
		var r := region_of[i]
		var res: int = regions["res_built"][r]
		var housed := mini(int(regions["latent_hh"][r]), res)
		@warning_ignore("integer_division")
		var households := units_col[i] * housed / maxi(res, 1)
		@warning_ignore("integer_division")
		var weight_pm := (radius_cm - roundi(sqrt(float(dist2)))) * 1000 / radius_cm
		var by_region: Dictionary = out["by_region"]
		by_region[codes[r]] = int(by_region.get(codes[r], 0)) + households * weight_pm
		out["parcels"] += 1
		out["households"] += households
	return out


## Bölge sütunlarında yapılı ya da boru hattındaki birimi `sign` (+1/-1) x birim kadar kaydırır.
static func _move_units(regions: Dictionary, r: int, stage: int, use: int, units: int, sign: int) -> void:
	if stage == EconomyState.STAGE_VACANT or stage == EconomyState.STAGE_TAKEN or use == EconomyConfig.USE_NONE:
		return
	var residential := use == EconomyConfig.USE_RESIDENTIAL
	var key: String
	if stage == EconomyState.STAGE_BUILT:
		key = "res_built" if residential else "com_built"
	else:
		key = "res_pipe" if residential else "com_pipe"
	var column: PackedInt64Array = regions[key]
	column[r] += sign * units
