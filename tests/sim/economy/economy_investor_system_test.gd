extends SimTestBase
## T-013 ölçüt 4 · Sistem düzeyi yatırımcı kararı (SIM-02/SIM-12): her karar `state.record_reason` ile gerekçeli; olumlu
## karar yatırımı başlatır, olumsuz karar sessiz değildir; örnekleme ve yatırımcı seçimi tohumlu RNG akışıyla
## deterministiktir.
## Periyodik tarama kapatılır (review_enabled = 0): yalnız imar sonrası dikkat değerlendirmesi ölçülür.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ISOLATE := {"decision": {"review_enabled": 0}}
const ALL_FACTORS: Array[StringName] = [
	&"reason.factor.demand", &"reason.factor.expected_return", &"reason.factor.construction_cost",
	&"reason.factor.infrastructure_capacity", &"reason.factor.financing", &"reason.factor.zoning_fit",
	&"reason.factor.market_sentiment",
]


func _patch(extra: Dictionary = {}) -> Dictionary:
	return S.merge(S.merge(ISOLATE, S.regions({"F1": S.favorable(), "F2": S.unfavorable()})), extra)


func _rezone(f: SimFacadeImpl, parcel_id: int, zone: StringName = &"zone.mixed") -> void:
	var result := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([parcel_id]), zone))
	assert_bool(result.is_rejected()).override_failure_message("imar komutu reddedildi: %s" % result.reason_key).is_false()


func _reasons(f: SimFacadeImpl, parcel_id: int) -> Array[ReasonRecord]:
	return f.reasons_for(SimContract.parcel_ref(parcel_id))


func test_rezoning_in_a_favorable_region_triggers_a_positive_reasoned_decision() -> void:
	var f := W.facade(_patch())
	var p := int(f.parcel_ids(S.R1)[0])
	_rezone(f, p)
	f.advance(12)
	var rs := _reasons(f, p)
	assert_int(rs.size()).override_failure_message("tam 1 karar kaydı").is_equal(1)
	var r := rs[0]
	assert_str(String(r.decision_key)).is_equal("decision.investor.develop")
	assert_str(String(r.outcome)).is_equal("positive")
	assert_str(String(r.actor.kind)).is_equal("investor")
	assert_bool(r.is_consistent()).override_failure_message(r.consistency_error()).is_true()
	assert_bool(r.subjects.has("command.1")).override_failure_message("kararı tetikleyen komut konu olmalı").is_true()
	assert_bool(r.subjects.has(String(SimContract.parcel_ref(p)))).is_true()
	var names: Array[StringName] = []
	for factor in r.factors:
		names.append(factor.name_key)
	assert_array(names).is_equal(ALL_FACTORS)


func test_rezoning_in_an_unfavorable_region_is_declined_with_a_recorded_reason() -> void:
	var f := W.facade(_patch())
	var p := int(f.parcel_ids(S.R2)[0])
	_rezone(f, p)
	f.advance(12)
	var rs := _reasons(f, p)
	assert_int(rs.size()).override_failure_message("olumsuz karar da kaydedilir (sessiz değil)").is_equal(1)
	assert_str(String(rs[0].outcome)).is_equal("negative")
	assert_bool(rs[0].is_consistent()).is_true()
	assert_str(String(W.stage_of(f, p))).is_equal("vacant")
	var declined := W.events(f, SimEvent.KIND_ACTOR_DECIDED).filter(
		func(e: SimEvent) -> bool: return e.message_key == &"event.investor.declined")
	assert_int(declined.size()).is_equal(1)
	assert_array(Array(declined[0].reason_ids)).is_equal([rs[0].id])
	assert_bool(declined[0].args.has("code")).override_failure_message("olay engelleyen kodu taşır").is_true()


func test_decision_happens_only_after_zoning_takes_effect_plus_attention_delay() -> void:
	var f := W.facade(_patch())
	var p := int(f.parcel_ids(S.R1)[0])
	_rezone(f, p)
	# komut tick 0 sınırında uygulanır (bekleyen), yürürlük 3. gün, dikkat gecikmesi 2 gün => karar tick 5
	f.advance(4)
	assert_int(_reasons(f, p).size()) \
		.override_failure_message("imar yürürlüğe girmeden/dikkat gecikmesi dolmadan karar yok") \
		.is_equal(0)
	f.advance(1)
	var rs := _reasons(f, p)
	assert_int(rs.size()).is_equal(1)
	assert_int(rs[0].tick).is_equal(5)


func test_without_any_trigger_nothing_is_evaluated_when_periodic_review_is_off() -> void:
	var f := W.facade(_patch())
	f.advance(40)
	assert_int(f.game_state().reasons.size()).is_equal(0)
	assert_int(f.last_event_seq()).is_equal(0)


func test_threshold_is_base_threshold_plus_the_chosen_investors_shift() -> void:
	var h := W.handle(_patch())
	var p := int(h.facade.parcel_ids(S.R2)[0])
	_rezone(h.facade, p)
	h.facade.advance(12)
	var r: ReasonRecord = _reasons(h.facade, p)[0]
	var shift: int = h.config.investors[r.actor.id - 1]["threshold_shift"]
	assert_int(r.threshold).is_equal(h.config.p("base_threshold") + shift)
	assert_str(String(r.actor.name_key)).is_equal("actor.investor.%d.name" % r.actor.id)


func test_factor_values_are_fixed_point_integers_within_range() -> void:
	var f := W.facade(_patch())
	for p in f.parcel_ids():
		_rezone(f, int(p))
	f.advance(15)
	assert_int(f.game_state().reasons.size()).is_greater(0)
	for p in f.parcel_ids():
		for r in _reasons(f, int(p)):
			for factor in r.factors:
				assert_int(factor.value).is_between(-1000, 1000)
				assert_int(factor.weight).is_between(0, 1000)


func test_approval_commits_investor_capital_and_records_the_flows() -> void:
	var h := W.handle(_patch())
	var capital_before: int = int(h.config.investors[0]["capital"]) * h.config.investors.size()
	var p := int(h.facade.parcel_ids(S.R1)[0])
	_rezone(h.facade, p)
	h.facade.advance(12)
	var d := W.data(h.facade)
	var rec := EconomyQuery.parcel_record(h.facade.game_state(), p)
	assert_str(String(rec["stage"])).is_equal("planned")
	var capital_after := 0
	for c: int in d["investors"]["capital"]:
		capital_after += c
	var totals := EconomyQuery.totals(h.facade.game_state())
	assert_int(totals["approvals"]).is_equal(1)
	assert_int(capital_before - capital_after).is_equal(totals["land_sales"] + totals["construction_spend"])
	assert_int(totals["land_sales"]).is_equal(FacadeTestSupport.LAND_VALUE)
	var unit_cost := h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "cost_per_unit")
	assert_int(totals["construction_spend"]).is_equal(rec["units"] * unit_cost)
	assert_int(rec["owner_id"]).is_greater(0)


func test_declines_with_an_unchanged_cause_are_not_logged_again_within_the_repeat_window() -> void:
	# Aynı parsel periyodik taramada tekrar tekrar reddedilir; kayıt taşmasın diye aynı kod 180 gün içinde yazılmaz.
	var patch := S.merge(S.regions({"F1": {"initial_households": 150, "infra_capacity_units": 5000}}),
		{"decision": {"review_period_days": 5, "prescreen_demand_pm": 0, "base_threshold": 1000000,
		"negative_repeat_days": 60, "decline_backoff_days": 0}})
	var h := W.handle(patch)
	h.facade.advance(130)
	var totals := EconomyQuery.totals(h.facade.game_state())
	assert_int(totals["declines"]).override_failure_message("çok sayıda değerlendirme").is_greater(40)
	var p := int(h.facade.parcel_ids(S.R1)[0])
	var logged := _reasons(h.facade, p).size()
	assert_int(logged).override_failure_message("her 60 günde en çok bir kayıt (130 gün => en çok 3)").is_between(1, 3)
	assert_int(totals["declines_recorded"]).is_less(totals["declines"])
	var recorded := h.facade.game_state().reasons.size()
	assert_int(recorded).is_equal(totals["declines_recorded"] + totals["approvals"])


func test_a_change_of_cause_is_logged_immediately() -> void:
	# Aynı parsel: önce talep yetersizliği, sonra altyapı kapanınca farklı kod => yeni kayıt.
	var patch := S.merge(S.regions({"F1": {"initial_households": 3, "infra_capacity_units": 5000}}),
		{"decision": {"review_period_days": 5, "prescreen_demand_pm": 0, "negative_repeat_days": 3650,
		"decline_backoff_days": 0}})
	var h := W.handle(patch)
	var p := int(h.facade.parcel_ids(S.R1)[0])
	h.facade.advance(20)
	var first := _reasons(h.facade, p).size()
	assert_int(first).is_equal(1)
	var regions: Dictionary = W.data(h.facade)["regions"]
	var cap: PackedInt64Array = regions["infra_cap"]
	cap[0] = 0
	h.facade.advance(20)
	assert_int(_reasons(h.facade, p).size()).override_failure_message("neden değişti: yeni kayıt").is_equal(2)


func test_investor_is_chosen_by_the_seeded_economy_stream() -> void:
	var actors := {}
	for seed_value in range(1, 13):
		var f := W.facade(_patch(), seed_value)
		var p := int(f.parcel_ids(S.R2)[0])
		_rezone(f, p)
		f.advance(8)
		var rs := _reasons(f, p)
		assert_int(rs.size()).is_equal(1)
		actors[rs[0].actor.id] = true
	assert_int(actors.size()).override_failure_message("yatırımcı seçimi tohuma göre değişmeli").is_greater(1)


func test_decisions_use_only_the_economy_rng_stream() -> void:
	var f := W.facade(_patch())
	_rezone(f, int(f.parcel_ids(S.R1)[0]))
	f.advance(10)
	var rng: RngStreams = f.game_state().rng
	assert_bool(rng.has_stream(&"economy")).is_true()
	assert_bool(rng.has_stream(&"decider")).is_false()


func test_same_seed_same_decisions_different_seed_different_sentiment() -> void:
	var a := W.facade(_patch(), 7)
	var b := W.facade(_patch(), 7)
	var c := W.facade(_patch(), 8)
	for f in [a, b, c]:
		for p in f.parcel_ids():
			_rezone(f, int(p))
		f.advance(15)
	assert_str(assert_hash(a.state_hash())).is_equal(b.state_hash())
	assert_str(c.state_hash()).override_failure_message("tohum kullanılmıyor").is_not_equal(a.state_hash())


func test_event_and_reason_prune_horizon_stays_consistent() -> void:
	# Olay saklama ufku gerekçe ufkundan uzun olamaz (ADR-0005 §5): ekonomi olayları bunu bozmaz.
	var f := W.facade(_patch())
	for p in f.parcel_ids():
		_rezone(f, int(p))
	f.advance(20)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_proposed_density_and_height_cap_flow_into_the_project_size() -> void:
	# CAN-05: yoğunluk ve yükseklik oyuncunun KOŞULUdur; proje büyüklüğünü (birim) değiştirir, bina yaratmaz.
	var cases := {"taban": [-1, -1, 10], "yogun": [2000, -1, 21], "alcak": [-1, 6, 5], "cok_alcak": [-1, 3, 2]}
	for label: String in cases:
		var f := W.facade(_patch())
		var p := int(f.parcel_ids(S.R1)[0])
		var params := {"parcel_ids": PackedInt64Array([p]), "land_use": &"zone.residential"}
		if cases[label][0] >= 0:
			params["density"] = cases[label][0]
		if cases[label][1] >= 0:
			params["max_height_m"] = cases[label][1]
		# base imar zaten konut: farklı bir imar yazarak dikkat tetiklenir, sonra aynı kullanım için yoğunluk/yükseklik
		params["land_use"] = &"zone.mixed"
		f.submit_command(SimCommand.make(&"zoning.propose", params))
		f.advance(8)
		var rec := EconomyQuery.parcel_record(f.game_state(), p)
		assert_str(String(rec["stage"])).override_failure_message(label).is_equal("planned")
		assert_int(rec["units"]).override_failure_message(label).is_equal(cases[label][2])


func test_declined_parcels_wait_out_the_backoff_before_being_reviewed_again() -> void:
	var base := {"regions": {"defaults": {"initial_households": 150, "infra_capacity_units": 5000}},
		"decision": {"review_period_days": 5, "prescreen_demand_pm": 0, "base_threshold": 1000000}}
	var eager := S.synthetic_handle(40, 1, S.merge(base, {"decision": {"decline_backoff_days": 0}}))
	var patient := S.synthetic_handle(40, 1, S.merge(base, {"decision": {"decline_backoff_days": 30}}))
	eager.facade.advance(100)
	patient.facade.advance(100)
	var eager_n: int = EconomyQuery.totals(eager.facade.game_state())["declines"]
	var patient_n: int = EconomyQuery.totals(patient.facade.game_state())["declines"]
	assert_int(patient_n).override_failure_message("bekleme yok sayılıyor: %d vs %d" % [patient_n, eager_n]) \
		.is_less(eager_n / 2)
	assert_int(patient_n).override_failure_message("her parsel en az bir kez değerlendirilmeli").is_greater_equal(40)


func test_review_budget_caps_evaluations_per_tick_without_starving_high_index_parcels() -> void:
	var patch := {"regions": {"defaults": {"initial_households": 150, "infra_capacity_units": 5000}},
		"decision": {"review_period_days": 5, "prescreen_demand_pm": 0, "base_threshold": 1000000,
		"decline_backoff_days": 0, "max_reviews_per_tick": 1}}
	var h := S.synthetic_handle(40, 1, patch)
	h.facade.advance(100)
	var evaluations: int = EconomyQuery.totals(h.facade.game_state())["evaluations"]
	assert_int(evaluations).override_failure_message("tick başına en çok 1 değerlendirme").is_less_equal(100)
	assert_int(evaluations).is_greater(30)
	var last_id := int(h.facade.parcel_ids()[39])
	assert_int(h.facade.reasons_for(SimContract.parcel_ref(last_id)).size()).override_failure_message(
		"imleç yüksek indeksli parseli aç bırakmamalı").is_greater(0)
