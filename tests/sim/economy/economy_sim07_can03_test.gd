extends SimTestBase
## T-013 ölçüt 6 · SIM-07 ve CAN-03 TESTLE:
## (a) altyapı/imar tek başına bina yaratmaz; (b) aynı imar iki koşulda: biri yatırım getirir, diğeri getirmez, ikisi
## de
##  gerekçeli; (c) belediye komutları yalnız koşulları değiştirir, `building.* / private.* / spawn.*` reddedilir ve özel
## gelişme gerekçeli bir yatırımcı kararı olmadan oluşmaz; (d) kısmi mekanikler (spekülasyon/altyapı yükü) açıkça
## sınanır.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ISOLATE := {"decision": {"review_enabled": 0}}


func _rezone_all(f: SimFacadeImpl, zone: StringName = &"zone.mixed") -> void:
	var result := f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), zone))
	assert_bool(result.is_rejected()).override_failure_message(String(result.reason_key)).is_false()


func _stages(f: SimFacadeImpl) -> Array[String]:
	var out: Array[String] = []
	for v in f.parcel_views(f.parcel_ids()):
		out.append(String(v.development))
	return out


func _reason_for(f: SimFacadeImpl, p: int) -> ReasonRecord:
	var rs := f.reasons_for(SimContract.parcel_ref(p))
	assert_int(rs.size()).override_failure_message("parsel %d için tam bir karar kaydı bekleniyordu" % p).is_equal(1)
	return rs[0]


# --- (a) Altyapı/imar tek başına bina yaratmaz ---

func test_zoning_with_ample_infrastructure_but_no_demand_never_creates_buildings() -> void:
	# Talep yok (hane 0), altyapı bol, tüm parseller karma imar: ufukta (400 gün) tek bina yok. Periyodik tarama AÇIK.
	var patch := {"regions": {"defaults": {"initial_households": 0, "infra_capacity_units": 100000, "access_pm": 1000,
		"service_pm": 1000}}}
	var h := W.handle(patch)
	_rezone_all(h.facade)
	h.facade.advance(400)
	for stage in _stages(h.facade):
		assert_str(stage).is_equal("vacant")
	assert_int(EconomyQuery.totals(h.facade.game_state())["approvals"]).is_equal(0)
	# Neden: her parsel için gerekçeli "yatırım gelmedi" kaydı vardır (SIM-12).
	for p in h.facade.parcel_ids():
		var r := h.facade.reasons_for(SimContract.parcel_ref(int(p)))
		assert_int(r.size()).override_failure_message("parsel %d gerekçesiz" % p).is_greater(0)
		assert_str(String(r[0].outcome)).is_equal("negative")


func test_raising_infrastructure_capacity_alone_does_not_start_investment() -> void:
	var h := W.handle(S.merge(ISOLATE, {"regions": {"defaults": {"initial_households": 0, "infra_capacity_units": 1}}}))
	_rezone_all(h.facade)
	h.facade.advance(10)
	var cap: PackedInt64Array = W.data(h.facade)["regions"]["infra_cap"]
	for r in cap.size():
		cap[r] = 1000000  # altyapı yatırımı (T-014 yazma noktası): koşul değişir, talep yine yok
	h.facade.advance(300)
	for stage in _stages(h.facade):
		assert_str(stage).is_equal("vacant")


func test_high_demand_where_zoning_forbids_private_use_never_creates_buildings() -> void:
	# Bol talep + bol altyapı, ama imar özel kullanıma kapalı (izinli kullanım yok): periyodik tarama AÇIK, 400 gün.
	var patch := {"regions": {"defaults": {"initial_households": 5000, "infra_capacity_units": 100000}},
		"zones": {"zone.residential": {"uses": []}}}
	var h := W.handle(patch)
	h.facade.advance(400)
	for stage in _stages(h.facade):
		assert_str(stage).is_equal("vacant")
	assert_int(EconomyQuery.totals(h.facade.game_state())["approvals"]).is_equal(0)


func test_unbuildable_zone_decision_is_recorded_once_with_the_zoning_blocker() -> void:
	var big := {"regions": {"defaults": {"initial_households": 5000, "infra_capacity_units": 100000}}}
	var h := W.handle(S.merge(ISOLATE, big))
	var p := int(h.facade.parcel_ids()[0])
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.green"))
	h.facade.advance(30)
	var r := _reason_for(h.facade, p)
	assert_str(String(r.outcome)).is_equal("negative")
	var zoning_factor: ReasonFactor = r.factors.filter(
		func(f: ReasonFactor) -> bool: return f.name_key == &"reason.factor.zoning_fit")[0]
	assert_int(zoning_factor.value).is_equal(-1000)
	var latest := h.facade.game_state().reasons.latest({"subject": "parcel.%d" % p})
	assert_str(String(latest["code"])).is_equal("zoning_not_buildable")


# --- (b) Aynı imar, iki koşul ---

func _same_command_two_conditions(world_seed: int) -> Array:
	var patch := S.merge(ISOLATE, S.regions({"F1": S.favorable(), "F2": S.unfavorable()}))
	var f := W.facade(patch, world_seed)
	var p1 := int(f.parcel_ids(S.R1)[0])
	var p2 := int(f.parcel_ids(S.R2)[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p1, p2]), &"zone.mixed"))  # TEK komut, iki parsel
	f.advance(12)
	return [f, p1, p2]


func test_same_zoning_command_develops_where_conditions_are_good_and_not_where_they_are_bad() -> void:
	for seed_value in range(1, 9):  # sonuç RNG gürültüsünden bağımsız olmalı
		var run := _same_command_two_conditions(seed_value)
		var f: SimFacadeImpl = run[0]
		var good := _reason_for(f, run[1])
		var bad := _reason_for(f, run[2])
		assert_str(String(good.outcome)).override_failure_message("seed %d: iyi koşul" % seed_value).is_equal("positive")
		assert_str(String(bad.outcome)).override_failure_message("seed %d: kötü koşul" % seed_value).is_equal("negative")
		assert_str(String(W.stage_of(f, run[1]))).is_equal("planned")
		assert_str(String(W.stage_of(f, run[2]))).is_equal("vacant")
		assert_bool(good.is_consistent() and bad.is_consistent()).is_true()
		assert_array(Array(good.subjects)).contains(["command.1"])
		assert_array(Array(bad.subjects)).contains(["command.1"])


func _factor_value(r: ReasonRecord, name: StringName) -> int:
	for f in r.factors:
		if f.name_key == name:
			return f.value
	return 0


func test_the_two_outcomes_are_explained_by_the_factors_that_differ() -> void:
	var run := _same_command_two_conditions(S.SEED)
	var good := _reason_for(run[0], run[1])
	var bad := _reason_for(run[0], run[2])
	assert_int(_factor_value(good, &"reason.factor.infrastructure_capacity")).is_greater_equal(0)
	assert_int(_factor_value(bad, &"reason.factor.infrastructure_capacity")) \
		.override_failure_message("kötü koşul: altyapı engeli") \
		.is_equal(-1000)
	assert_int(_factor_value(good, &"reason.factor.demand")).is_greater(_factor_value(bad, &"reason.factor.demand"))
	assert_int(good.score).is_greater_equal(good.threshold)
	assert_int(bad.score).is_less(bad.threshold)


func test_demand_and_infrastructure_each_gate_investment_two_by_two_matrix() -> void:
	var cases := {
		"yuksek_talep_yeterli_altyapi": [{"initial_households": 400, "infra_capacity_units": 2000}, "positive"],
		"dusuk_talep_yeterli_altyapi": [{"initial_households": 3, "infra_capacity_units": 2000}, "negative"],
		"yuksek_talep_yetersiz_altyapi": [{"initial_households": 400, "infra_capacity_units": 4}, "negative"],
		"dusuk_talep_yetersiz_altyapi": [{"initial_households": 3, "infra_capacity_units": 4}, "negative"],
	}
	for label: String in cases:
		var f := W.facade(S.merge(ISOLATE, S.regions({"F1": cases[label][0]})))
		var p := int(f.parcel_ids(S.R1)[0])
		f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.mixed"))
		f.advance(12)
		var r := _reason_for(f, p)
		assert_str(String(r.outcome)).override_failure_message(label).is_equal(cases[label][1])
		var expected_stage := "planned" if cases[label][1] == "positive" else "vacant"
		assert_str(String(W.stage_of(f, p))).override_failure_message(label).is_equal(expected_stage)


func test_the_declined_parcel_stays_declined_and_the_log_says_why_in_the_event() -> void:
	var run := _same_command_two_conditions(S.SEED)
	var f: SimFacadeImpl = run[0]
	var declined := W.events(f, SimEvent.KIND_ACTOR_DECIDED).filter(
		func(e: SimEvent) -> bool: return e.message_key == &"event.investor.declined")
	assert_int(declined.size()).is_equal(1)
	assert_str(String(declined[0].args["code"])).is_equal("infrastructure_exhausted")
	f.advance(200)
	assert_str(String(W.stage_of(f, run[2]))).is_equal("vacant")


# --- (c) CAN-03: belediye koşulu değiştirir, bina yaratmaz ---

func test_forbidden_command_kinds_are_rejected_and_change_nothing() -> void:
	var h := W.handle(S.merge(ISOLATE, S.regions({"F1": S.favorable()})))
	var f := h.facade
	f.advance(2)
	var hash_before := f.state_hash()
	var p := PackedInt64Array([f.parcel_ids(S.R1)[0]])
	for kind in [&"building.place", &"building.demolish", &"private.build", &"private.invest", &"spawn.house",
			&"spawn.factory"]:
		var result := f.submit_command(SimCommand.make(kind, {"parcel_ids": p}))
		assert_bool(result.is_rejected()).override_failure_message(String(kind)).is_true()
		assert_str(String(result.reason_key)) \
			.override_failure_message(String(kind)) \
			.is_equal(String(CommandResult.REJECT_NOT_A_MAYOR_VERB))
	assert_str(f.state_hash()).override_failure_message("reddedilen komut durumu değiştirdi").is_equal(hash_before)
	f.advance(50)
	for stage in _stages(f):
		assert_str(stage).is_equal("vacant")


func test_forbidden_kinds_cannot_be_smuggled_past_the_facade_through_the_raw_command_queue() -> void:
	# Facade'ı atlayıp ham kuyruğa koysak bile işleyici yok: gerekçeli ret, durum değişmez.
	var h := W.handle(S.merge(ISOLATE, S.regions({"F1": S.favorable()})))
	var f := h.facade
	var p := f.parcel_ids(S.R1)[0]
	Commands.submit(f.game_state(), &"building.place", {"parcel_ids": PackedInt64Array([p])})
	Commands.submit(f.game_state(), &"spawn.house", {"parcel_id": p})
	f.advance(30)
	for stage in _stages(f):
		assert_str(stage).is_equal("vacant")
	assert_int(Commands.rejected(f.game_state()).size()).is_equal(2)
	assert_int(EconomyQuery.totals(f.game_state())["approvals"]).is_equal(0)


func test_every_catalog_command_leaves_development_to_actor_decisions() -> void:
	# Katalogdaki HER komut türü uygulanır; hiçbiri gelişmeyi doğrudan yazmaz: aynı tick'te `vacant` kalır, ilk
	# `planned` ancak gerekçeli bir yatırımcı kararından sonra görünür.
	var h := W.handle(S.merge(ISOLATE, S.regions({"F1": S.favorable()})))
	var f := h.facade
	var p := PackedInt64Array([f.parcel_ids(S.R1)[0]])
	var sample := {
		&"zoning.propose": {"parcel_ids": p, "land_use": &"zone.mixed", "density": 1500, "max_height_m": 12},
		&"budget.propose": {"lines": {&"budget.line.roads": 1000}},
	}
	for kind: StringName in SimCommand.CATALOG:
		assert_bool(sample.has(kind)).override_failure_message("katalogda örneği olmayan komut: %s" % kind).is_true()
		f.submit_command(SimCommand.make(kind, sample[kind]))
	for t in 4:
		f.advance(1)
		assert_str(String(W.stage_of(f, p[0]))).override_failure_message("tick %d" % f.current_tick()).is_equal("vacant")
	f.advance(10)
	assert_str(String(W.stage_of(f, p[0]))).is_equal("planned")
	assert_int(_reason_for(f, p[0]).tick).is_less_equal(f.current_tick())


func test_every_private_development_is_preceded_by_a_positive_investor_reason() -> void:
	# Otonom büyüme AÇIK, bol talep: 250 günde en az bir proje; her gelişen parselin olumlu yatırımcı gerekçesi var ve
	# onaydan ÖNCE gelişme yok; onay sayısı = boş olmayan parsel sayısı (başka bir yol yok).
	var h := W.handle(S.regions({"F1": S.favorable(), "F2": S.favorable()}))
	var f := h.facade
	f.advance(250)
	var developed := 0
	for v in f.parcel_views(f.parcel_ids()):
		if v.development == &"vacant":
			continue
		developed += 1
		var positives := f.reasons_for(v.ref()).filter(func(r: ReasonRecord) -> bool: return r.outcome == &"positive")
		assert_int(positives.size()).override_failure_message("parsel %d gerekçesiz geliştirildi" % v.id).is_equal(1)
		assert_str(String(positives[0].decision_key)).is_equal("decision.investor.develop")
		assert_int(positives[0].actor.id).is_equal(v.owner.id)
	assert_int(developed).is_greater(0)
	assert_int(developed).is_equal(EconomyQuery.totals(f.game_state())["approvals"])


func test_without_the_economy_installed_no_command_ever_develops_a_parcel() -> void:
	var f := FacadeTestSupport.facade(3)
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
	f.advance(200)
	for v in f.parcel_views(f.parcel_ids()):
		assert_str(String(v.development)).is_equal("vacant")


# --- (d) Kısmi mekanikler ---

func test_wrong_density_strains_infrastructure_and_slows_investment() -> void:
	# Yoğunluk x3: proje başına birim ve altyapı yükü x3; aynı kapasitede çok daha az proje onaylanır (altyapı çabuk
	# dolar). Belediye bütçesine/bakım maliyetine bağlanması T-014: burada yalnız altyapı yükü ölçülür (kısmi mekanik).
	var base := {"regions": {"defaults": {"initial_households": 600, "infra_capacity_units": 60}}}
	var low := W.handle(base)
	var high := W.handle(S.merge(base, {"zones": {"zone.residential": {"uses": ["residential"], "density_pm": 3000}}}))
	low.facade.advance(120)
	high.facade.advance(120)
	var low_totals := EconomyQuery.totals(low.facade.game_state())
	var high_totals := EconomyQuery.totals(high.facade.game_state())
	assert_int(high_totals["approvals"]) \
		.override_failure_message("aynı kapasitede yoğun imar daha az proje") \
		.is_less(low_totals["approvals"])
	assert_int(high_totals["approvals"]).is_greater(0)
	var per_project := func(h: EconomyHandle, totals: Dictionary) -> int:
		var load := 0
		for row in EconomyQuery.region_stats(h.facade.game_state(), h.config):
			assert_int(row["infra_load"]).override_failure_message("kapasite aşılmaz").is_less_equal(row["infra_cap"])
			load += row["infra_load"]
		return load / totals["approvals"]
	assert_int(per_project.call(high, high_totals)).override_failure_message("proje başına altyapı yükü") \
		.is_greater(per_project.call(low, low_totals))
