extends SimTestBase
## T-013 ölçüt 5 · Kademeli gelişme (SIM-03/08): başlatılan yatırım `development_stage` aşamalarından ZAMANLA ilerler
## (süreler veri), olaylar `SimEventLog` ile (SIM-12), durum `ParcelView.development`'e yansır; altyapı kapasitesi
## düşerse inşaat durur ve kapasite dönünce sürer. Periyodik tarama kapalı: tek parsel, tek komut.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const PATCH := {
	"decision": {"review_enabled": 0},
	"regions": {"overrides": {"F1": {"initial_households": 400, "infra_capacity_units": 2000}}},
}
const ALLOWED_EDGES := {
	"vacant": ["vacant", "planned"], "planned": ["planned", "under_construction"],
	"under_construction": ["under_construction", "stalled", "built"], "stalled": ["stalled", "under_construction"],
	"built": ["built"],
}


## Komutla imarlanmış tek parsel (F1) ve onaylanana dek ilerletilmiş (karar tick'i 5) facade.
func _started() -> Array:
	var h := W.handle(PATCH)
	var p := int(h.facade.parcel_ids(S.R1)[0])
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.mixed"))
	h.facade.advance(5)
	return [h, p]


func _stage(f: SimFacadeImpl, p: int) -> String:
	return String(W.stage_of(f, p))


func _parcel_events(f: SimFacadeImpl, p: int) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.subjects.has(String(SimContract.parcel_ref(p))) and e.kind != SimEvent.KIND_COMMAND_APPLIED:
			out.append(e)
	return out


func test_stage_durations_follow_the_configured_plan_and_construction_days() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	assert_str(_stage(h.facade, p)).is_equal("planned")
	var decided := h.facade.current_tick()
	var units: int = EconomyQuery.parcel_record(h.facade.game_state(), p)["units"]
	var plan_days := h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "plan_days")
	var build_days := h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "construction_base_days") \
		+ units * h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "construction_days_per_unit")
	var started_tick := -1
	var built_tick := -1
	for t in range(decided + 1, decided + plan_days + build_days + 10):
		h.facade.advance(1)
		if started_tick < 0 and _stage(h.facade, p) == "under_construction":
			started_tick = t
		if built_tick < 0 and _stage(h.facade, p) == "built":
			built_tick = t
	assert_int(started_tick).override_failure_message("planned süresi plan_days").is_equal(decided + plan_days)
	assert_int(built_tick - started_tick) \
		.override_failure_message("inşaat süresi = taban + birim x gün/birim") \
		.is_equal(build_days)


func test_stages_advance_only_along_allowed_edges_one_tick_at_a_time() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	var last := _stage(h.facade, p)
	var seen: Array[String] = [last]
	for t in 130:
		h.facade.advance(1)
		var now := _stage(h.facade, p)
		assert_bool((ALLOWED_EDGES[last] as Array).has(now)).override_failure_message("%s -> %s" % [last, now]).is_true()
		if now != last:
			seen.append(now)
		last = now
	assert_array(seen).is_equal(["planned", "under_construction", "built"])


func test_nothing_is_built_instantly_the_decision_tick_shows_planned_not_built() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	assert_str(_stage(h.facade, started[1])).is_not_equal("built")
	assert_int(EconomyQuery.parcel_record(h.facade.game_state(), started[1])["days_left"]).is_greater(5)


func test_events_tell_decision_start_and_completion_with_the_deciding_reason() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	h.facade.advance(130)
	var reason_id: int = h.facade.reasons_for(SimContract.parcel_ref(p))[0].id
	var keys: Array[String] = []
	for e in _parcel_events(h.facade, p):
		keys.append(String(e.message_key))
		if e.message_key in [&"event.investor.develop", &"event.construction.started", &"event.construction.completed"]:
			assert_array(Array(e.reason_ids)) \
				.override_failure_message("%s gerekçe kimliği" % e.message_key) \
				.is_equal([reason_id])
	assert_array(keys).is_equal(["event.zoning.applied", "event.investor.develop", "event.construction.started",
		"event.construction.completed"])
	var kinds: Array[StringName] = []
	for e in _parcel_events(h.facade, p):
		kinds.append(e.kind)
	assert_array(kinds).is_equal([SimEvent.KIND_PARCEL_CHANGED, SimEvent.KIND_ACTOR_DECIDED, SimEvent.KIND_PARCEL_CHANGED,
		SimEvent.KIND_PARCEL_CHANGED])


func test_parcel_view_reports_stage_owner_and_unchanged_land_value() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	h.facade.advance(20)
	var view := h.facade.parcel_views(PackedInt64Array([p]))[0]
	assert_str(String(view.development)).is_equal("under_construction")
	assert_object(view.owner).is_not_null()
	assert_str(String(view.owner.kind)).is_equal("investor")
	assert_int(view.owner.id).is_between(1, h.config.investors.size())
	assert_int(view.land_value).is_equal(FacadeTestSupport.LAND_VALUE)
	assert_int(view.reason_ids.size()).override_failure_message("denetçi gerekçeyi görür").is_greater(0)
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()


func test_pipeline_lowers_demand_at_once_and_completion_moves_units_to_built_supply() -> void:
	# Kazanç 500: talep endeksi 1000'e doyup farkı gizlemesin.
	var h := W.handle(S.merge(PATCH, {"decision": {"demand_gain_pm": 500}}))
	var p := int(h.facade.parcel_ids(S.R1)[0])
	h.facade.advance(1)
	var before: Dictionary = EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.mixed"))
	h.facade.advance(5)
	var units: int = EconomyQuery.parcel_record(h.facade.game_state(), p)["units"]
	var pipe: Dictionary = EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]
	assert_int(pipe["res_pipe"]).is_equal(units)
	assert_int(pipe["res_built"]).is_equal(0)
	assert_int(pipe["demand_res_pm"]) \
		.override_failure_message("arz boru hattında: talep düşer") \
		.is_less(before["demand_res_pm"])
	assert_int(pipe["infra_load"]).override_failure_message("altyapı yükü boru hattını sayar").is_equal(units)
	h.facade.advance(130)
	var done: Dictionary = EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]
	assert_int(done["res_pipe"]).is_equal(0)
	assert_int(done["res_built"]).is_equal(units)
	assert_int(EconomyQuery.totals(h.facade.game_state())["completions"]).is_equal(1)


func test_built_parcels_are_not_evaluated_again() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	h.facade.advance(130)
	var count := h.facade.game_state().reasons.size()
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.commercial"))
	h.facade.advance(40)
	assert_int(h.facade.game_state().reasons.size()) \
		.override_failure_message("yapılı parsel yeniden değerlendirilmez") \
		.is_equal(count)
	assert_str(_stage(h.facade, p)).is_equal("built")


func test_construction_stalls_when_capacity_drops_and_resumes_when_it_returns() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	h.facade.advance(20)
	assert_str(_stage(h.facade, p)).is_equal("under_construction")
	var cap: PackedInt64Array = W.data(h.facade)["regions"]["infra_cap"]
	var original := cap[0]
	cap[0] = 0
	h.facade.advance(1)
	assert_str(_stage(h.facade, p)).is_equal("stalled")
	var frozen: int = EconomyQuery.parcel_record(h.facade.game_state(), p)["days_left"]
	h.facade.advance(15)
	assert_str(_stage(h.facade, p)).is_equal("stalled")
	assert_int(EconomyQuery.parcel_record(h.facade.game_state(), p)["days_left"]) \
		.override_failure_message("durmuşken süre işlemez") \
		.is_equal(frozen)
	cap[0] = original
	h.facade.advance(1)
	assert_str(_stage(h.facade, p)).is_equal("under_construction")
	h.facade.advance(frozen + 2)
	assert_str(_stage(h.facade, p)).is_equal("built")
	var keys: Array[String] = []
	for e in _parcel_events(h.facade, p):
		keys.append(String(e.message_key))
	assert_array(keys).contains(["event.construction.stalled", "event.construction.resumed",
		"event.construction.completed"])


func test_stall_and_resume_are_reasoned_decisions_of_the_owning_investor() -> void:
	var started := _started()
	var h: EconomyHandle = started[0]
	var p: int = started[1]
	h.facade.advance(20)
	var cap: PackedInt64Array = W.data(h.facade)["regions"]["infra_cap"]
	var original := cap[0]
	cap[0] = 0
	h.facade.advance(2)
	cap[0] = original
	h.facade.advance(2)
	var rs := h.facade.reasons_for(SimContract.parcel_ref(p))
	assert_int(rs.size()).is_equal(3)
	var owner_id: int = EconomyQuery.parcel_record(h.facade.game_state(), p)["owner_id"]
	assert_str(String(rs[1].decision_key)).is_equal("decision.investor.continue")
	assert_str(String(rs[1].outcome)).override_failure_message("durma = devam etmeme kararı").is_equal("negative")
	assert_str(String(rs[2].outcome)).is_equal("positive")
	for r in rs:
		assert_bool(r.is_consistent()).is_true()
		assert_int(r.actor.id).is_equal(owner_id)
	assert_array(Array(rs[1].parent_ids)) \
		.override_failure_message("durma kararı onay kararına bağlanır") \
		.is_equal([rs[0].id])


func test_existing_stock_parcels_never_enter_the_pipeline() -> void:
	var probe := W.facade(PATCH)
	var p := int(probe.parcel_ids(S.R1)[0])
	var stock := ListStockSource.create([{"parcel_id": p, "use": &"residential", "units": 10, "owner": 0}])
	var h := W.handle(PATCH, S.SEED, S.PER_REGION, stock)
	h.facade.advance(30)
	assert_str(_stage(h.facade, p)).is_equal("built")
	assert_int(EconomyQuery.totals(h.facade.game_state())["approvals"]).is_equal(0)
	assert_int(EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]["res_pipe"]).is_equal(0)
