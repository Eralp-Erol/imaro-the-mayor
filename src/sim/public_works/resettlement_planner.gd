class_name ResettlementPlanner
extends RefCounted
## T-065 Aşama 1 · Kamulaştırmada YENİDEN İSKÂN planı (D-015/D-016, spec `resettlement-social-security-v0.md` §3.0/§4,
## ADR-0009 B). SAF ve durumsuz: `plan`/`allocate` durumu DEĞİŞTİRMEZ (önizleme ve onay AYNI hesabı kullanır, ölçüt 8),
## `apply_moves`/`revert_moves` yalnız bölge `latent_hh` sütununu yazar. Rastgelelik yok; sıralama (sınıf, mesafe, kod)
## kanoniktir. CAN-03: yalnız MEVCUT boş konut birimini okur; hiçbir parsel/bina/birim sütunu yazılmaz, bina yaratılmaz.
## SIM-07: ev yoksa yoktur; `unplaced` gerçek sayıdır, sahte "karşılandı" yoktur.
##
## Üç ayrı denetim, tek puan yok (SIM-09): KAPASİTE (hedef bölgenin boş evi; bir yol en çok `max_fill_pm` alır), KİRA
## (hedef kira <= kaynak kira x (1000 + tolerans)), YER (hedef bölgenin yola en yakın yapılı konut parseli
## `max_distance_m` içinde). Üçü de tamamsa TAM ev; kapasite var ve kira/yer şartından YALNIZ biri aşıldıysa KISMİ ev
## (tepki `partial_relief_pm` kadar azalır); ikisi de aşıldıysa ev SAYILMAZ (N-3). Tam evler kısmilerden önce, sonra
## yola yakın olan, sonra bölge kodu sırasıyla kullanılır.
##
## Kalan tepki (`effective`, kaynak bölge başına): ev bulunamayan hane TAM sayılır; tam ev bulunan hane
## `residual_reaction_pm`, kısmi ev bulunan hane `max(residual, 1000 - partial_relief_pm)` ağırlığıyla; toplam
## binde birde YUKARI yuvarlanır (ev bulunan aile varsa en az 1 kalır: "biraz kalsın", D-016 §2).
##
## Tahsis kaydı (`works[i].expropriation.resettlement`, yalnız politika AÇIK ve yerinden edilen > 0 iken):
##   moves        [[kaynak_kod, hedef_kod, hane]...] hane > 0; kaynak koda, sonra hedef sırasına göre
##   rehoused     taşınan toplam hane (= Σ moves)     unplaced   ev bulunamayan toplam hane
##   partial      rehoused'ın kısmi evlere giden payı  cost       gösterge bedel (hane x hedefin birim bedeli)
##   residual_pm  hesapta kullanılan tam-ev kalan tepkisi (‰)
##   unplaced_by  {kod: hane}  yalnız > 0      effective  {kod: tepki ağırlıklı hane}  yerinden edilen her kaynak kod
##   weight_by    {kod: ‰ ağırlıklı hane}  effective'in yuvarlanmamış payı (effective = ceil(weight_by / 1000)); bekleme
##                listesi (T-067) ev verildikçe bunu günceller, yuvarlama hatası birikmez
##   served       [[tick, kaynak, hedef, hane, sınıf (0 tam, 1 kısmi), kaynaktan_düştü (0/1)]...] YALNIZ T-067 bekleme
##                listesinden sonradan verilen evler (yoksa alan yok); rehoused = Σ moves + Σ served

const PM := 1000
const FAR := 9223372036854775807  # menzil dışı hedefin sıralama anahtarı (en sona)
const CLASS_FULL := 0
const CLASS_PARTIAL := 1


## Saf tahsis. `sources`: [{code, displaced, rent}] (sırası önemsiz; yerinden edilen 0 olan atlanır), `targets`:
## [{code, vacancy, rent, unit_cost, dist2}] (`dist2` < 0: yer şartı aşıldı). Sonuç: kayıt şeması (yukarıda).
static func allocate(sources: Array, targets: Array, cfg: ResettlementConfig) -> Dictionary:
	var out := {"moves": [], "rehoused": 0, "unplaced": 0, "partial": 0, "cost": 0,
		"residual_pm": cfg.residual_reaction_pm, "unplaced_by": {}, "effective": {}, "weight_by": {}}
	var ordered: Array = sources.filter(func(s: Dictionary) -> bool: return int(s["displaced"]) > 0)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["code"]) < String(b["code"]))
	var room := {}  # hedef kod -> bu yolun kalan payı (özgün boşluğun max_fill_pm'i; kaynaklar arasında ORTAK)
	for t: Dictionary in targets:
		room[String(t["code"])] = int(t["vacancy"]) * cfg.max_fill_pm / PM
	var partial_weight := maxi(cfg.residual_reaction_pm, PM - cfg.partial_relief_pm)
	for s: Dictionary in ordered:
		var code := String(s["code"])
		var left := int(s["displaced"])
		var full := 0
		var part := 0
		for cand: Dictionary in candidates(s, targets, cfg):
			var target_code := String(cand["code"])
			var take := mini(left, int(room[target_code]))
			if take <= 0:
				continue
			room[target_code] = int(room[target_code]) - take
			left -= take
			(out["moves"] as Array).append([code, target_code, take])
			out["cost"] = int(out["cost"]) + take * int(cand["unit_cost"])
			if int(cand["class"]) == CLASS_FULL:
				full += take
			else:
				part += take
		out["rehoused"] = int(out["rehoused"]) + full + part
		out["partial"] = int(out["partial"]) + part
		out["unplaced"] = int(out["unplaced"]) + left
		if left > 0:
			(out["unplaced_by"] as Dictionary)[code] = left
		var weight := left * PM + full * cfg.residual_reaction_pm + part * partial_weight
		(out["weight_by"] as Dictionary)[code] = weight
		(out["effective"] as Dictionary)[code] = (weight + PM - 1) / PM
	return out


## Bu kaynak için kullanılabilir hedefler, (sınıf, mesafe, kod) sırasıyla; ikisi de aşılanlar (ev sayılmaz) yok.
## `ResettlementQueue` (T-067) aynı kuralı bekleme listesi için kullanır.
static func candidates(source: Dictionary, targets: Array, cfg: ResettlementConfig) -> Array:
	var out: Array = []
	for t: Dictionary in targets:
		if int(t["vacancy"]) <= 0:
			continue
		var rent_ok := int(t["rent"]) * PM <= int(source["rent"]) * (PM + cfg.rent_tolerance_pm)
		var place_ok := int(t["dist2"]) >= 0
		if not rent_ok and not place_ok:
			continue
		out.append({"code": String(t["code"]), "unit_cost": int(t["unit_cost"]),
			"class": CLASS_FULL if (rent_ok and place_ok) else CLASS_PARTIAL,
			"dist": int(t["dist2"]) if place_ok else FAR})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["class"] != b["class"]:
			return int(a["class"]) < int(b["class"])
		if a["dist"] != b["dist"]:
			return int(a["dist"]) < int(b["dist"])
		return String(a["code"]) < String(b["code"]))
	return out


## Kamulaştırma planı (`ParcelExpropriation.plan` çıktısı) için tahsis. Durumu DEĞİŞTİRMEZ. `points`: yol çizgisi
## [[x, z]...] cm (yer şartı: yola uzaklık); `econ`: kira için ekonomi yapılandırması. Yerinden edilen yoksa {}.
static func plan(state: GameState, cols: Dictionary, expropriation: Dictionary, points: Array,
		cfg: ResettlementConfig, econ: EconomyConfig) -> Dictionary:
	var d := EconomyState.data(state)
	var displaced: Dictionary = expropriation["displaced"]
	if d.is_empty() or displaced.is_empty():
		return {}
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var removed := _removed_res(d, expropriation["rows"])
	var sources: Array = []
	for code: String in displaced:
		sources.append({"code": code, "displaced": int(displaced[code]), "rent": _rent(econ, regions, codes.find(code))})
	var open_regions := {}  # boş evi olan, yerinden edilmeyen bölgeler: indeks -> boş birim
	for r in codes.size():
		if displaced.has(codes[r]):
			continue  # yıkımdan sonra boş ev kalmaz (yerinden edilen > 0 <=> yıkım sonrası talep > arz)
		var vacancy: int = int(regions["res_built"][r]) - int(removed.get(r, 0)) - int(regions["latent_hh"][r])
		if vacancy > 0:
			open_regions[r] = vacancy
	var distances := _distances(d, cols, expropriation["rows"], points, cfg.max_distance_m * 100, open_regions)
	var targets: Array = []
	for r: int in open_regions:
		var unit_rent := econ.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month")
		var mult := _rent_mult(econ, regions, r)
		targets.append({"code": codes[r], "vacancy": open_regions[r], "rent": unit_rent * mult,
			"unit_cost": unit_rent * mult * cfg.support_months / PM + cfg.move_grant,
			"dist2": int(distances.get(r, -1))})
	return allocate(sources, targets, cfg)


## Hane kaynak -> hedef aktarımı (yalnız `latent_hh`; bina yaratılmaz). Kayıttaki `moves` uygulanır.
static func apply_moves(state: GameState, record: Dictionary) -> void:
	var regions: Dictionary = EconomyState.data(state)["regions"]
	var codes: PackedStringArray = regions["codes"]
	var latent: PackedInt64Array = regions["latent_hh"]
	for move: Array in record["moves"]:
		latent[codes.find(String(move[0]))] -= int(move[2])
		latent[codes.find(String(move[1]))] += int(move[2])


## Geri alma: aktarım TERS sırada geri sarılır; hedef bölge arada azaldıysa dönen hane kırpılır (`latent_hh`
## negatife düşmez; ADR-0009 Değişiklik 2). Gerçekte dönen hane sayısı döner (olaydaki `rehoused_returned`).
## Bekleme listesinden SONRADAN verilen evler (`served`, T-067) yol anındaki aktarımdan önce, ters sırada geri alınır.
static func revert_moves(state: GameState, record: Dictionary) -> int:
	var regions: Dictionary = EconomyState.data(state)["regions"]
	var codes: PackedStringArray = regions["codes"]
	var latent: PackedInt64Array = regions["latent_hh"]
	var returned := 0
	var served: Array = record.get("served", [])
	for k in range(served.size() - 1, -1, -1):
		var row: Array = served[k]
		var source := codes.find(String(row[1]))
		var target := codes.find(String(row[2]))
		if source < 0 or target < 0:
			continue
		var back := mini(int(row[3]), int(latent[target]))
		latent[target] -= back
		if int(row[5]) == 1:  # aile kaynak bölgenin talebinden alınmıştı (ayrılma kaderinde alınmamıştı)
			latent[source] += back
		returned += back
	var moves: Array = record["moves"]
	for k in range(moves.size() - 1, -1, -1):
		var source := codes.find(String((moves[k] as Array)[0]))
		var target := codes.find(String((moves[k] as Array)[1]))
		if source < 0 or target < 0:
			continue
		var back := mini(int((moves[k] as Array)[2]), int(latent[target]))
		latent[target] -= back
		latent[source] += back
		returned += back
	return returned


## Bölge indeksi -> yıkılan YAPILI konut birimi (alınan satırlardan; plan satırı: {id, i, r}).
static func _removed_res(d: Dictionary, rows: Array) -> Dictionary:
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var out := {}
	for row: Dictionary in rows:
		var i: int = row["i"]
		if stage[i] == EconomyState.STAGE_BUILT and use_col[i] == EconomyConfig.USE_RESIDENTIAL:
			out[int(row["r"])] = int(out.get(int(row["r"]), 0)) + units_col[i]
	return out


## İstenen bölgelerin (indeks) yola en yakın YAPILI konut parselinin uzaklığının karesi (cm^2); `radius_cm` dışındakiler
## sözlükte YOK (yer şartı aşıldı). O(parsel): kutu ön elemesi, sonra tam uzaklık. Alınan parseller sayılmaz.
static func _distances(d: Dictionary, cols: Dictionary, rows: Array, pts: Array, radius_cm: int,
		wanted: Dictionary) -> Dictionary:
	var out := {}
	if wanted.is_empty() or pts.size() < 2:
		return out
	var taken := {}
	for row: Dictionary in rows:
		taken[int(row["i"])] = true
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
	var radius2 := radius_cm * radius_cm
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var region_of: PackedInt32Array = cols["region_of"]
	var cx: PackedInt64Array = cols["center_x"]
	var cz: PackedInt64Array = cols["center_z"]
	for i in stage.size():
		if stage[i] != EconomyState.STAGE_BUILT or use_col[i] != EconomyConfig.USE_RESIDENTIAL \
				or not wanted.has(region_of[i]) or taken.has(i):
			continue
		if cx[i] < min_x or cx[i] > max_x or cz[i] < min_z or cz[i] > max_z:
			continue
		var dist2 := PriorityReview.dist2_to_polyline(cx[i], cz[i], pts)
		if dist2 <= radius2 and (not out.has(region_of[i]) or dist2 < int(out[region_of[i]])):
			out[region_of[i]] = dist2
	return out


## Bölgenin kira çarpanı ‰ (talep endeksinden; ekonomi çekirdeğinin kendi formülü).
static func _rent_mult(econ: EconomyConfig, regions: Dictionary, r: int) -> int:
	var demand := EconomyMath.region_demand_pm(econ, regions, r, EconomyConfig.USE_RESIDENTIAL, 0)
	return EconomyMath.rent_mult_pm(demand, econ.p("rent_floor_pm"), econ.p("rent_cap_pm"))


## Karşılaştırma ölçeği: birim kira x çarpan (binde birde; bölme yok). `ResettlementQueue` da kullanır.
static func rent_of(econ: EconomyConfig, regions: Dictionary, r: int) -> int:
	return _rent(econ, regions, r)


static func _rent(econ: EconomyConfig, regions: Dictionary, r: int) -> int:
	return econ.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month") * _rent_mult(econ, regions, r)
