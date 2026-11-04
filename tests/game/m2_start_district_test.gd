extends GdUnitTestSuite
## M2 kapanış madde 1 (F03 ölçüt 7 · WLD-12, CAN-08, D-002): "örnek ilçe zorunlu başlangıç yeri olmaz" — çekirdek döngü
## (yol çiz -> kamulaştır -> imar -> yatırımcı yapı) birden çok ilçe kimliği ve dünya tohumuyla çalışır. Başsız; sahne
## YOK: oyunun `_build_buildings`/`_start_sim` kurulumunun aynısı (gerçek Ismeral verisi + ağ + T0 yerleşimi +
## PlayableEconomy/PlayablePolitics + gerçek kamulaştırma köprüsü), `tests/sim/perf/qa_world_support.gd` üzerinden.
## Ilçe kodları VERİDEN okunur (`world.regions`); bu dosyada ilçe sabiti yok. Kapsam sınırı: kamera açılışı için yalnız
## `CameraPresets.start_view` sınanır; `--start-district` bayrağının sahne yolu (world_preview) burada koşmaz.
## Bilinen boşluk B-026: yol yetki alanı (`network.json jurisdiction_regions`) başlangıç ilçesine bağlı DEĞİL, veride
## yalnız test alanı D2'dir; ilçe başına döngü testleri yetki alanını başlangıç ilçesine ayarlar (veri parametresi), bu
## ayarsız durum `test_shipped_jurisdiction_*` ile olduğu gibi kaydedilir.

const Q := preload("res://tests/sim/perf/qa_world_support.gd")
const WARM_DAYS := 30
const RUN_DAYS := 260
const CONTROL_DAYS := 200
const CANDIDATE_POOL := 120
const NEAR_M := 150.0
const PLAN_PARCELS := 6
const PLAN_ZONE := &"zone.mixed"
const OTHER_WORLD_SEED := 20261104
const KEY_ROAD := "event.road.built"
const KEY_EXPROPRIATED := "event.road.expropriated"
const KEY_APPLIED := "event.zoning.applied"
const KEY_STARTED := "event.construction.started"
const KEY_COMPLETED := "event.construction.completed"

static var _worlds: Dictionary = {}


## Dünya tohumu başına bir kez kurulur (≈15-20 sn); testler ağı her koşu sonunda taban grafına döndürür.
static func _world(world_seed: int) -> Q.WorldCtx:
	if not _worlds.has(world_seed):
		_worlds[world_seed] = Q.build_world(world_seed)
	return _worlds[world_seed]


static func _default_seed() -> int:
	return int(WorldControlData.load_dir(Q.DATA_DIR)["world"]["default_seed"])


static func _codes(w: Q.WorldCtx) -> Array[StringName]:
	var out: Array[StringName] = []
	for r in w.world.regions:
		out.append(r.code)
	return out


## Yetki alanı: yalnız başlangıç ilçesi (veri parametresi; `jurisdiction_regions` ile aynı alan).
static func _set_jurisdiction(w: Q.WorldCtx, codes: Array[StringName]) -> void:
	w.road_rules.jurisdiction_regions = codes.duplicate()


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Yola en yakın (<= NEAR_M) BOŞ (T0 stoksuz) ve yolun ALMADIĞI parseller; sıralı, deterministik.
static func _plan_ids(w: Q.WorldCtx, code: StringName, pts: PackedVector2Array, taken: PackedInt64Array,
		count: int) -> PackedInt64Array:
	var occupied := {}
	for pid in w.settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	var gone := {}
	for pid in taken:
		gone[int(pid)] = true
	var scored: Array = []
	for v in w.views:
		if v.region_code != code or occupied.has(v.id) or gone.has(v.id):
			continue
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt64Array()
	for k in mini(count, scored.size()):
		out.append(int(scored[k][1]))
	return out


## Bölgede kamulaştırmalı geçerli yol adaylarından, çevresinde en çok plan parseli olanı (eşitlikte üretim sırası).
static func _pick(w: Q.WorldCtx, s: Q.SimCtx, code: StringName, stream: String) -> Dictionary:
	var best: Dictionary = {}
	var best_n := -1
	for c in Q.region_candidates(w, s, String(code), CANDIDATE_POOL, stream):
		var pts: PackedVector2Array = c["pts"]
		var taken := RoadDraftCheck.taken_parcels(w.net, pts, RoadDrawTool.ROAD_CLASS)
		var ids := _plan_ids(w, code, pts, taken, PLAN_PARCELS)
		if ids.size() > best_n:
			best_n = ids.size()
			best = {"cand": c, "plan_ids": ids, "taken": taken}
	return best


## Senaryodan sonra oyuncu yollarını geri al ve ağın taban grafına döndüğünü doğrula.
func _restore(w: Q.WorldCtx, s: Q.SimCtx) -> void:
	for _i in 8:
		if not bool(s.ctx.undo_live_op()["ok"]):
			break
	assert_str(w.net.graph_hash()).override_failure_message("ağ taban grafına dönmedi").is_equal(w.base_hash)


## Bir ilçede çekirdek döngü: ısınma -> yol (kamulaştırmalı) -> imar -> RUN_DAYS gün.
## `with_plan` false = kontrol (imarsız).
func _run_district(w: Q.WorldCtx, code: StringName, sim_seed: int = -1, with_plan: bool = true) -> Dictionary:
	_set_jurisdiction(w, [code] as Array[StringName])
	var s := Q.new_sim(w, sim_seed, true)
	assert_object(s).override_failure_message("sim kurulamadı (%s)" % code).is_not_null()
	s.step(WARM_DAYS)
	var pick := _pick(w, s, code, "m2_start_district_" + String(code))
	assert_bool(pick.is_empty()).override_failure_message("%s: yol adayı yok" % code).is_false()
	var cand: Dictionary = pick["cand"]
	var plan_ids: PackedInt64Array = pick["plan_ids"]
	var out := {"code": code, "sim": s, "plan_ids": plan_ids, "taken": pick["taken"], "cand": cand}
	var road := s.facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
	out["road_status"] = road.status
	out["road_reason"] = road.reason_key
	s.step(2)
	if with_plan:
		var plan := s.facade.submit_command(SimCommand.zoning_propose(plan_ids, PLAN_ZONE))
		out["plan_status"] = plan.status
		out["plan_reason"] = plan.reason_key
	# Gün gün: yatırımcı gerekçeleri sim günlüğünde SINIRLI süre kalır (B-027: kapasite 1000, ~110 gün); karar anında oku.
	var positive_seen := {}
	for _d in (RUN_DAYS if with_plan else CONTROL_DAYS):
		s.step(1)
		for id in plan_ids:
			if positive_seen.has(int(id)):
				continue
			for rec in s.facade.reasons_for(SimContract.parcel_ref(int(id))):
				if rec.decision_key == &"decision.investor.develop" and rec.outcome == ReasonRecord.OUTCOME_POSITIVE:
					positive_seen[int(id)] = true
	out["positive_seen"] = positive_seen
	out["hash"] = s.facade.state_hash()
	out["totals"] = EconomyQuery.totals(s.facade.game_state())
	return out


func _built_by_sim(f: SimFacadeImpl, ids: PackedInt64Array) -> Array[int]:
	var out: Array[int] = []
	for v in f.parcel_views(ids):
		if v.developed_by_sim and v.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION,
				ParcelView.DEVELOPMENT_BUILT]:
			out.append(v.id)
	return out


## Bölgeden bağımsız: sim'in geliştirdiği her parsel (CAN-03/D-010: yalnız oyuncunun imar planındakiler).
func _all_sim_developed(f: SimFacadeImpl) -> Array[int]:
	var out: Array[int] = []
	for v in f.parcel_views(f.parcel_ids()):
		if v.developed_by_sim:
			out.append(v.id)
	return out


func _check_loop(r: Dictionary) -> void:
	var code: StringName = r["code"]
	var s: Q.SimCtx = r["sim"]
	var f := s.facade
	var plan_ids: PackedInt64Array = r["plan_ids"]
	var tag := String(code)
	# Yol: komut kabul, kamulaştırma ve yapım olayı, alınan parseller artık "taken".
	assert_str(String(r["road_status"])).override_failure_message("%s yol komutu: %s" % [tag, r["road_reason"]]) \
			.is_equal(String(CommandResult.STATUS_QUEUED))
	assert_int(int(s.counts.get(KEY_ROAD, 0))).override_failure_message(tag + ": yol yapılmadı").is_equal(1)
	assert_int(int(s.counts.get(KEY_EXPROPRIATED, 0))).override_failure_message(tag + ": kamulaştırma olayı yok") \
			.is_equal(1)
	var taken: PackedInt64Array = r["taken"]
	assert_int(taken.size()).override_failure_message(tag + ": kamulaştırma parsel almadı").is_greater(0)
	for v in f.parcel_views(taken):
		assert_str(String(v.development)).override_failure_message("%s parsel %d alınmadı" % [tag, v.id]) \
				.is_equal(String(ParcelView.DEVELOPMENT_TAKEN))
	# İmar: plan kabul, yürürlük olayı, her plan parselinin gerekçesi var (SIM-12).
	assert_int(plan_ids.size()).override_failure_message(tag + ": plan parseli yok").is_greater(0)
	assert_str(String(r["plan_status"])).override_failure_message("%s imar komutu: %s" % [tag, r["plan_reason"]]) \
			.is_equal(String(CommandResult.STATUS_QUEUED))
	assert_int(int(s.counts.get(KEY_APPLIED, 0))).override_failure_message(tag + ": imar yürürlüğe girmedi") \
			.is_equal(plan_ids.size())
	# Yatırımcı: en az bir plan parseli yapıldı; inşaat başladı ve bitti; olumlu karar kayıtlı.
	var built := _built_by_sim(f, plan_ids)
	assert_int(built.size()).override_failure_message("%s: hiçbir plan parseline yapı çıkmadı: %s" % [tag, s.counts]) \
			.is_greater(0)
	assert_int(int(s.counts.get(KEY_STARTED, 0))).is_greater(0)
	assert_int(int(s.counts.get(KEY_COMPLETED, 0))).is_greater(0)
	assert_int(int(r["totals"]["approvals"])).is_equal(int(s.counts.get("event.investor.develop", 0)))
	var positive_seen: Dictionary = r["positive_seen"]
	for id in built:  # SIM-12: yapının arkasında karar anında yazılmış olumlu gerekçe
		assert_bool(positive_seen.has(id)).override_failure_message(
				"%s parsel %d: olumlu yatırım gerekçesi görülmedi" % [tag, id]).is_true()
	# CAN-03/D-010: sim'in geliştirdiği her parsel (tüm ilçeler) oyuncunun imar planındaki parsellerden biri.
	for id in _all_sim_developed(f):
		assert_bool(plan_ids.has(id)).override_failure_message("%s: plansız parsel %d geliştirildi" % [tag, id]) \
				.is_true()


# --- 1) Kamera açılışı: her ilçe veriden, kodda sabit yok -------------------------------------------------------------

func test_start_view_opens_on_each_district_from_data_and_falls_back_to_core_for_unknown_codes() -> void:
	var w := _world(_default_seed())
	var codes := _codes(w)
	assert_int(codes.size()).override_failure_message("en az iki ilçe kimliği gerekir").is_greater_equal(2)
	var ground := func(x: float, z: float) -> float: return maxf(w.world.height_at(x, z), w.world.sea_level)
	var focuses := {}
	for code in codes:
		var r := CameraPresets.start_view(w.world, code, ground)
		assert_bool(r["ok"]).override_failure_message(String(code)).is_true()
		assert_str(String(r["name"])).is_equal("district")
		var st: CameraState = r["state"]
		assert_str(String(w.world.region_code_at(st.focus_x, st.focus_z))).override_failure_message(
				"%s: odak başka ilçede" % code).is_equal(String(code))
		focuses[Vector2(st.focus_x, st.focus_z)] = true
	assert_int(focuses.size()).override_failure_message("ilçeler aynı odağa açılıyor").is_equal(codes.size())
	for none in [&"", &"ZZ9"]:
		assert_str(String(CameraPresets.start_view(w.world, none, ground)["name"])).is_equal("core")


# --- 2) Çekirdek döngü her ilçede (yetki alanı = başlangıç ilçesi) ---------------------------------------------

func test_core_loop_road_expropriate_zone_build_runs_in_every_district_of_the_default_world() -> void:
	var w := _world(_default_seed())
	var hashes := {}
	for code in _codes(w):
		var r := _run_district(w, code)
		_check_loop(r)
		hashes[String(r["hash"])] = true
		_restore(w, r["sim"])
	assert_int(hashes.size()).override_failure_message("farklı ilçeler aynı sim durumunu verdi") \
			.is_equal(_codes(w).size())


func test_core_loop_also_runs_on_a_different_world_seed_in_two_districts() -> void:
	var w := _world(_default_seed())
	var other := _world(OTHER_WORLD_SEED)
	assert_str(other.net.graph_hash()).override_failure_message("farklı tohum aynı dünyayı verdi") \
			.is_not_equal(w.net.graph_hash())
	var codes := _codes(other)
	assert_int(codes.size()).is_greater_equal(2)
	for code in codes.slice(0, 2):
		var r := _run_district(other, code)
		_check_loop(r)
		_restore(other, r["sim"])


# --- 3) CAN-03 / D-010: yol tek başına yapı doğurmaz (iki ilçe) ------------------------------------------------

func test_road_without_a_zoning_plan_builds_nothing_in_two_districts() -> void:
	var w := _world(_default_seed())
	for code in _codes(w).slice(0, 2):
		var r := _run_district(w, code, -1, false)
		var s: Q.SimCtx = r["sim"]
		assert_str(String(r["road_status"])).override_failure_message("%s: %s" % [code, r["road_reason"]]) \
				.is_equal(String(CommandResult.STATUS_QUEUED))
		assert_int(int(s.counts.get(KEY_ROAD, 0))).is_equal(1)
		assert_int(int(r["totals"]["approvals"])).override_failure_message("%s: planı olmayan arazide yapı" % code) \
				.is_equal(0)
		assert_array(_all_sim_developed(s.facade)).override_failure_message(code).is_empty()
		_restore(w, s)


# --- 4) Determinizm -----------------------------------------------------------------------------------------------

func test_same_district_and_seed_give_the_same_hash_and_a_different_seed_or_district_does_not() -> void:
	var w := _world(_default_seed())
	var codes := _codes(w).slice(0, 2)
	var first := {}
	for code in codes:
		var a := _run_district(w, code)
		_restore(w, a["sim"])
		var b := _run_district(w, code)
		_restore(w, b["sim"])
		assert_str(String(a["hash"])).override_failure_message("%s: aynı tohum, farklı hash" % code) \
				.is_equal(String(b["hash"]))
		first[code] = String(a["hash"])
	assert_str(String(first[codes[0]])).override_failure_message("farklı ilçe aynı hash").is_not_equal(
			String(first[codes[1]]))
	var c := _run_district(w, codes[0], _default_seed() + 1)
	_restore(w, c["sim"])
	assert_str(String(c["hash"])).override_failure_message("farklı sim tohumu aynı hash") \
			.is_not_equal(String(first[codes[0]]))


# --- 5) Bilinen boşluk B-026: gönderilen veri yol yetkisini yalnız D2'ye bağlıyor ---------------------------------

## KARAKTERİZASYON (B-026): `network.json jurisdiction_regions` başlangıç ilçesinden bağımsız sabit veri. Yetki alanı
## dışındaki ilçede yol çizimi `outside_jurisdiction` ile reddedilir; yani o ilçede başlayan oyuncu yol çizemez ve
## yatırımcı döngüsü (yol -> kapasite) başlamaz. Boşluk kapanınca (yetki başlangıç ilçesini izleyince) bu test
## GÜNCELLENİR.
func test_shipped_jurisdiction_data_allows_roads_only_in_listed_districts_b022() -> void:
	var w := _world(_default_seed())
	var rules := RoadDraftRules.load_path(Q.NETWORK_PATH)
	_set_jurisdiction(w, rules.jurisdiction_regions)
	var s := Q.new_sim(w, -1, true)
	s.step(WARM_DAYS)
	var blocked := 0
	for code in _codes(w):
		var tally := {}
		var cands := Q.region_candidates(w, s, String(code), 40, "m2_b022_" + String(code), tally)
		if rules.allows_region(code):
			assert_bool(cands.is_empty()).override_failure_message("%s: yetkili ilçede yol yok" % code).is_false()
		else:
			blocked += 1
			assert_bool(cands.is_empty()).override_failure_message("%s: yetki dışı ama yol kabul" % code).is_true()
			assert_int(int(tally.get("public_work.reject.outside_jurisdiction", 0))).override_failure_message(
					"%s: ret nedeni outside_jurisdiction değil: %s" % [code, tally]).is_greater(0)
	assert_int(blocked).override_failure_message("B-026 kapandıysa bu testi güncelleyin").is_greater(0)
	_restore(w, s)
