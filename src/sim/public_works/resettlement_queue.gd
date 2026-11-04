class_name ResettlementQueue
extends RefCounted
## T-067 (D-019 E1, "sıraya girsinler") · Ev bulunamayan ailelerin BEKLEME LİSTESİ. SAF ve statik; rastgelelik yok.
##
## Liste türetilir, ayrı nesne yoktur: bekleyen aile = bir yolun yeniden iskân kaydındaki `unplaced_by` ({kaynak bölge:
## hane}). Sıra kanoniktir: yol sırası (`works[]`, yani komut sırası, eskiden yeniye), sonra bölge kodu. Hane kimliği
## yoktur (hane = bölge toplamı, cohort modeli; hane başı nesne kapsam dışı). Yıkılmış yolun kaydı da sayılır (yıkım
## tepki satırlarını silmez); geri alınan yolun kaydı gider.
##
## "Sonradan bitirilen yeni ev" = bir bölgenin yapılı konut sütununun (`res_built`) artışı. Bu sütunu YALNIZ yatırımcı
## tamamlaması artırır (CAN-03: belediye komutu artıramaz); `PolicyState.QUEUE_KEY.built_mark` son bakılan değeri tutar.
## Bölüm YALNIZ bekleyen aile varken yaratılır, liste boşalınca silinir; politika hiç açılmadıysa hiç yoktur
## (`sync` ilk satırda döner): GOLDEN_A/B/X bit-bit aynıdır.
##
## `serve` her gün ekonomiden SONRA çalışır (`ResettlementQueueSystem`); yalnız politika AÇIKKEN. Hedef bölge başına
## verilebilecek hane iki şeyi aşmaz: yeni birim ve GERÇEKTEN boş birim (`max(res_built - latent_hh, 0)`; SIM-07: boş
## olmayan eve "eve kavuştu" denmez). Aynı bölgeye dönen aile (hane kaderi `return_to_latent`, kaynak = hedef) zaten o
## bölgenin `latent_hh`indedir: üst sınır yeni birim ve o anda ev arayan sayısıdır, `latent_hh` değişmez, yalnız "ev
## verildi" işlenir. Kural T-065 ile aynıdır (kapasite + kira + yer -> tam / kısmi / ev sayılmaz; `max_fill_pm`
## uygulanmaz: sıradaki aileler yeni evin öncelikli sahibidir). Tepki: kayıttaki `weight_by`/`effective` güncellenir;
## okuma yine TEK noktada `ReactionRehousing`'tedir (ADR-0009 Değişiklik 1), defter ham kalır.
## Sıradan verilen evin bedeli bütçeye YAZILMAZ (bütçe yolu bir kez yazar; gerçek para kısıtı T-014/Q-003 AÇIK).

const DECISION := &"decision.municipal.resettlement_queue"
const FACTOR_SERVED := &"reason.factor.queue_served_households"
const FACTOR_WAITING := &"reason.factor.queue_waiting_households"
const FACTOR_NEW_UNITS := &"reason.factor.queue_new_units"
const PM := 1000


## Bekleme listesi bölümü var mı? (Bölüm yaratmaz.)
static func exists(state: GameState) -> bool:
	return PolicyState.data(state).has(PolicyState.QUEUE_KEY)


## Bekleyen aile sayısı (tüm yollar). Bölüm yaratmaz, durumu değiştirmez.
static func waiting_total(state: GameState) -> int:
	var total := 0
	for entry in _entries(state):
		total += int((entry["record"] as Dictionary)["unplaced"])
	return total


## Bölge kodu -> bekleyen aile (yalnız > 0).
static func waiting_by_region(state: GameState) -> Dictionary:
	var out := {}
	for entry in _entries(state):
		var by: Dictionary = (entry["record"] as Dictionary)["unplaced_by"]
		for code: String in by:
			out[code] = int(out.get(code, 0)) + int(by[code])
	return out


## Bekleme listesinden SONRADAN verilen toplam ev (hane).
static func served_total(state: GameState) -> int:
	var total := 0
	for entry in _entries(state):
		for row: Array in (entry["record"] as Dictionary).get("served", []):
			total += int(row[3])
	return total


## Liste ile `built_mark` bölümünü eşitler: bekleyen aile varsa bölüm vardır ve işaret şimdiki `res_built`tir (bu
## andan sonra biten ev "yeni"dir); yoksa bölüm silinir. Politika bölümü hiç yoksa HİÇBİR ŞEY yapmaz. Çağrılır: yol
## kamulaştırması uygulanınca/geri alınınca (yıkım `res_built`ı düşürür, geri alma yükseltir: yeni ev sayılmaz) ve
## politika değişince (kapalıyken biten evler yeni sayılmaz).
static func sync(state: GameState) -> void:
	var policy := PolicyState.data(state)
	if policy.is_empty():
		return
	if waiting_total(state) <= 0:
		policy.erase(PolicyState.QUEUE_KEY)
		return
	var d := EconomyState.data(state)
	if d.is_empty():
		return
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var built: PackedInt64Array = regions["res_built"]
	var mark := {}
	for r in codes.size():
		mark[codes[r]] = built[r]
	policy[PolicyState.QUEUE_KEY] = {"built_mark": mark}


## Günlük: yeni biten evleri bekleyen ailelere ver. Politika kapalıysa, liste yoksa ya da ekonomi kurulu değilse
## hiçbir şey yapmaz.
static func serve(state: GameState, ctx: PublicWorksContext) -> void:
	if ctx.economy == null or not ctx.config.resettlement.available \
			or not PolicyState.enabled(state, PolicyView.ID_RESETTLEMENT):
		return
	var policy := PolicyState.data(state)
	var d := EconomyState.data(state)
	if not policy.has(PolicyState.QUEUE_KEY) or d.is_empty():
		return
	var regions: Dictionary = d["regions"]
	var codes: PackedStringArray = regions["codes"]
	var built: PackedInt64Array = regions["res_built"]
	var latent: PackedInt64Array = regions["latent_hh"]
	var mark: Dictionary = policy[PolicyState.QUEUE_KEY]["built_mark"]
	var fresh := PackedInt64Array()  # bölge başına yeni biten konut birimi
	fresh.resize(codes.size())
	var any_new := false
	for r in codes.size():
		fresh[r] = maxi(built[r] - int(mark.get(codes[r], built[r])), 0)
		any_new = any_new or fresh[r] > 0
		if int(mark.get(codes[r], -1)) != built[r]:
			mark[codes[r]] = built[r]
	if not any_new:
		return
	var vacancy := PackedInt64Array()  # gerçekten boş birim (yeni birimler dahil)
	var seekers := PackedInt64Array()  # yeni birimler eklenmeden önce ev arayan hane
	vacancy.resize(codes.size())
	seekers.resize(codes.size())
	for r in codes.size():
		vacancy[r] = maxi(built[r] - latent[r], 0)
		seekers[r] = maxi(latent[r] - (built[r] - fresh[r]), 0)
	var pools := {"fresh0": fresh.duplicate(), "fresh": fresh, "vacancy": vacancy, "seekers": seekers}
	var env := {"d": d, "cols": ctx.economy.static_columns(), "econ": ctx.economy.config(), "regions": regions,
		"cfg": _queue_config(ctx.config.resettlement), "rents": {}, "places": {}}
	for entry in _entries(state, true):
		_serve_entry(state, entry, pools, env)
	if waiting_total(state) <= 0:
		policy.erase(PolicyState.QUEUE_KEY)


# --- iç ---

## Bekleme listesi hesabının yapılandırması: T-065 ile AYNI, yalnız `max_fill_pm` yok (sıra öncelikli sahiptir).
static func _queue_config(base: ResettlementConfig) -> ResettlementConfig:
	var cfg := ResettlementConfig.new()
	cfg.available = base.available
	cfg.max_fill_pm = PM
	cfg.rent_tolerance_pm = base.rent_tolerance_pm
	cfg.max_distance_m = base.max_distance_m
	cfg.partial_relief_pm = base.partial_relief_pm
	cfg.residual_reaction_pm = base.residual_reaction_pm
	cfg.support_months = base.support_months
	cfg.move_grant = base.move_grant
	return cfg


## Tahsis kaydı olan yollar, yol sırasıyla (eskiden yeniye): [{command_id, record, parcel_ids, returns}]. `returns`:
## hane kaderi `return_to_latent` (aile kaynak bölgenin talebinde). `only_waiting`: yalnız bekleyeni olanlar. `record`
## durumdaki sözlüğün kendisidir (değer kopyası DEĞİL).
static func _entries(state: GameState, only_waiting: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var section := PublicWorksState.data(state)
	if section.is_empty():
		return out
	for work: Dictionary in section["works"]:
		if not PublicWorksState.is_road_work(work):
			continue
		var record := PublicWorksState.resettlement_of(work)
		if record.is_empty() or (only_waiting and int(record["unplaced"]) <= 0):
			continue
		var taken: Dictionary = work["expropriation"]
		out.append({"command_id": int(work["command_id"]), "record": record, "parcel_ids": taken["parcel_ids"],
			"returns": String(taken.get("fate", "")) != String(ParcelExpropriation.FATE_LEAVE)})
	return out


## Bir yolun bekleyen ailelerini (bölge kodu sırasıyla) yeni evlerle eşleştirir.
static func _serve_entry(state: GameState, entry: Dictionary, pools: Dictionary, env: Dictionary) -> void:
	var record: Dictionary = entry["record"]
	var regions: Dictionary = env["regions"]
	var codes: PackedStringArray = regions["codes"]
	var fresh: PackedInt64Array = pools["fresh"]
	var vacancy: PackedInt64Array = pools["vacancy"]
	var seekers: PackedInt64Array = pools["seekers"]
	var returns: bool = entry["returns"]
	var sources: Array = (record["unplaced_by"] as Dictionary).keys()
	sources.sort()
	for code: String in sources:
		var s := codes.find(code)
		var waiting := int((record["unplaced_by"] as Dictionary)[code])
		if s < 0 or waiting <= 0:
			continue
		var targets: Array = []
		var limits := {}
		for t in codes.size():
			var limit := mini(fresh[t], seekers[t] if (returns and t == s) else vacancy[t])
			if limit <= 0:
				continue
			limits[codes[t]] = limit
			targets.append({"code": codes[t], "vacancy": limit, "rent": _rent(env, t), "unit_cost": 0,
				"dist2": _place_dist2(env, entry, t)})
		var source := {"code": code, "rent": _rent(env, s)}
		for cand: Dictionary in ResettlementPlanner.candidates(source, targets, env["cfg"]):
			var take := mini(waiting, int(limits[cand["code"]]))
			if take <= 0:
				continue
			_give(state, entry, code, codes.find(String(cand["code"])), take, int(cand["class"]), waiting, pools, env)
			waiting -= take
			if waiting <= 0:
				break


## `take` aileye `t` bölgesindeki yeni evden ev verir: `latent_hh` taşınır (ayrılma kaderinde yalnız eklenir), kayıt ve
## havuzlar güncellenir, gerekçe yazılır.
@warning_ignore("integer_division")
static func _give(state: GameState, entry: Dictionary, code: String, t: int, take: int, cls: int, waiting_before: int,
		pools: Dictionary, env: Dictionary) -> void:
	var record: Dictionary = entry["record"]
	var regions: Dictionary = env["regions"]
	var cfg: ResettlementConfig = env["cfg"]
	var codes: PackedStringArray = regions["codes"]
	var latent: PackedInt64Array = regions["latent_hh"]
	var fresh: PackedInt64Array = pools["fresh"]
	var vacancy: PackedInt64Array = pools["vacancy"]
	var seekers: PackedInt64Array = pools["seekers"]
	var s := codes.find(code)
	var from_latent := 1 if bool(entry["returns"]) else 0
	if from_latent == 1:
		latent[s] -= take
	latent[t] += take
	fresh[t] -= take
	if from_latent == 1 and s == t:
		seekers[t] -= take
	else:
		vacancy[t] -= take
		if from_latent == 1:
			seekers[s] = maxi(seekers[s] - take, 0)
	var by: Dictionary = record["unplaced_by"]
	if waiting_before - take > 0:
		by[code] = waiting_before - take
	else:
		by.erase(code)
	record["unplaced"] = int(record["unplaced"]) - take
	record["rehoused"] = int(record["rehoused"]) + take
	if cls == ResettlementPlanner.CLASS_PARTIAL:
		record["partial"] = int(record["partial"]) + take
	var residual := int(record["residual_pm"])
	var weight_after_pm := residual
	if cls == ResettlementPlanner.CLASS_PARTIAL:
		weight_after_pm = maxi(residual, PM - cfg.partial_relief_pm)
	var weights: Dictionary = record.get("weight_by", {})
	var effective: Dictionary = record["effective"]
	var weight := maxi(int(weights.get(code, int(effective.get(code, 0)) * PM)) + take * (weight_after_pm - PM), 0)
	weights[code] = weight
	record["weight_by"] = weights
	effective[code] = (weight + PM - 1) / PM
	var served: Array = record.get("served", [])
	served.append([state.tick, code, codes[t], take, cls, from_latent])
	record["served"] = served
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, int(entry["command_id"])))
	state.record_reason(ExpropriationFlow.ACTOR, DECISION, [
		{"name": FACTOR_SERVED, "value": take, "source_ref": ref},
		{"name": FACTOR_WAITING, "value": waiting_before, "weight": 0},
		{"name": FACTOR_NEW_UNITS, "value": int((pools["fresh0"] as PackedInt64Array)[t]), "weight": 0}], 0,
		&"resettlement_queue", PackedStringArray([ref]))


## Bölgenin kira ölçeği (bu `serve` çağrısında bir kez hesaplanır).
static func _rent(env: Dictionary, r: int) -> int:
	var rents: Dictionary = env["rents"]
	if not rents.has(r):
		rents[r] = ResettlementPlanner.rent_of(env["econ"], env["regions"], r)
	return int(rents[r])


## Yer şartı: `r` bölgesinin, yolun ALDIĞI parsellere en yakın yapılı konut parselinin uzaklığının karesi (cm^2);
## `max_distance_m` dışındaysa -1 (şart aşıldı). Bu `serve` çağrısında (yol, bölge) başına bir kez hesaplanır.
static func _place_dist2(env: Dictionary, entry: Dictionary, r: int) -> int:
	var key := "%d|%d" % [entry["command_id"], r]
	var places: Dictionary = env["places"]
	if places.has(key):
		return int(places[key])
	var d: Dictionary = env["d"]
	var cols: Dictionary = env["cols"]
	var radius_cm := (env["cfg"] as ResettlementConfig).max_distance_m * 100
	var radius2 := radius_cm * radius_cm
	var cx: PackedInt64Array = cols["center_x"]
	var cz: PackedInt64Array = cols["center_z"]
	var region_of: PackedInt32Array = cols["region_of"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var taken: Array = []
	for id: int in entry["parcel_ids"]:
		var i := EconomyState.index_of(d, id)
		if i >= 0:
			taken.append([cx[i], cz[i]])
	var best := -1
	for i in stage.size():
		if stage[i] != EconomyState.STAGE_BUILT or use_col[i] != EconomyConfig.USE_RESIDENTIAL or region_of[i] != r:
			continue
		for center: Array in taken:
			var dx: int = cx[i] - center[0]
			var dz: int = cz[i] - center[1]
			var dist2 := dx * dx + dz * dz
			if dist2 <= radius2 and (best < 0 or dist2 < best):
				best = dist2
	places[key] = best
	return best
