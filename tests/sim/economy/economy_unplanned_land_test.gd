extends SimTestBase
## T-043A (sim yarısı) · Plansız arazi (D-010, core-loop-v0 §2): `decision.unplanned_land_enabled` = 1
## iken T0'da gelişmemiş
## ve yürürlükte oyuncu planı olmayan parsel `unplanned`'dir: yatırımcı `zoning_unplanned` gerekçesiyle reddeder
## (placeholder `_base_zone` yok sayılır), plan yürürlüğe girince engel kalkar, kapasite/talep/getiri kararı ayrıdır.
## Yeni durum sütunu YOKTUR: durum `parcels.overlay` kayıtlarından türer. CAN-03: yeni komut türü yok.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ENABLED := {"decision": {"unplanned_land_enabled": 1}}
const UNPLANNED_CODE := "zoning_unplanned"
const F_UNPLANNED := &"reason.factor.zoning_unplanned"
const F_ZONING := &"reason.factor.zoning_fit"
const F_INFRA := &"reason.factor.infrastructure_capacity"
const VETO := -1000
## Komut 0. tickte verilir, 1. tickte uygulanır, `apply_delay_days` (3) sonra (4. tick) yürürlüğe girer.
const PLAN_IN_FORCE_TICK := 4


## Elverişli iki bölge (talep + kapasite bol) + bayrak.
func _favorable(extra: Dictionary = {}) -> Dictionary:
	return S.merge(S.merge(ENABLED, S.regions({"F1": S.favorable(), "F2": S.favorable()})), extra)


func _records(f: SimFacadeImpl, parcel_id: int) -> Array:
	return f.game_state().reasons.find({"subject": String(SimContract.parcel_ref(parcel_id))})


## Plan yürürlüğe girdikten SONRAKİ kayıtlar (öncesinde parsel plansızdı ve `zoning_unplanned` kaydı doğaldır).
func _records_since(f: SimFacadeImpl, parcel_id: int, tick: int) -> Array:
	return _records(f, parcel_id).filter(func(rec: Dictionary) -> bool: return int(rec["tick"]) >= tick)


func _factor(record: Dictionary, name: StringName) -> Dictionary:
	for factor: Dictionary in record["factors"]:
		if factor["name"] == name:
			return factor
	return {}


func _approvals(f: SimFacadeImpl) -> int:
	return int(EconomyQuery.totals(f.game_state()).get("approvals", 0))


func _vacant_all(f: SimFacadeImpl) -> bool:
	for v in f.parcel_views(f.parcel_ids()):
		if v.development != ParcelView.DEVELOPMENT_VACANT:
			return false
	return true


# --- Yapılandırma ---

func test_flag_is_off_by_default_and_read_from_data() -> void:
	assert_int(S.config().p("unplanned_land_enabled")).is_equal(0)
	assert_int(S.config(ENABLED).p("unplanned_land_enabled")).is_equal(1)
	assert_bool(EconomyConfig.from_dict(S.merge(S.raw_config(), {"decision": {"unplanned_land_enabled": 2}})).is_valid()) \
		.override_failure_message("bayrak yalnız 0|1").is_false()


# --- Ölçüt 1/7: bayrak durumu değiştirmez ---

func test_flag_does_not_change_the_state_hash_at_tick_zero() -> void:
	var off := W.facade(S.regions({"F1": S.favorable()}))
	var on := W.facade(S.merge(ENABLED, S.regions({"F1": S.favorable()})))
	assert_str(on.state_hash()).is_equal(off.state_hash())


func test_unplanned_run_without_any_proposal_writes_no_overlay_and_no_parcels_section() -> void:
	var f := W.facade(_favorable())
	f.advance(120)
	assert_bool(f.game_state().systems.has("parcels")) \
		.override_failure_message("teklifsiz koşuda `parcels` bindirmesi yaratılmamalı").is_false()


# --- Ölçüt 2: plansız boş parsel -> bina 0, her ret `zoning_unplanned` ---

func test_unplanned_vacant_land_gets_no_building_and_every_recorded_decision_names_the_missing_plan() -> void:
	var f := W.facade(_favorable())
	f.advance(200)
	assert_bool(_vacant_all(f)).override_failure_message("plansız arazide bina çıktı").is_true()
	assert_int(_approvals(f)).is_equal(0)
	var evaluated := int(EconomyQuery.totals(f.game_state())["evaluations"])
	assert_int(evaluated).override_failure_message("yatırımcı hiç değerlendirmedi").is_greater(0)
	var recorded := 0
	for p in f.parcel_ids():
		for rec: Dictionary in _records(f, int(p)):
			recorded += 1
			assert_str(String(rec["code"])).is_equal(UNPLANNED_CODE)
			assert_str(String(rec["outcome"])).is_equal("negative")
			assert_int(_factor(rec, F_UNPLANNED).get("value", 0)).override_failure_message("plan yok etkeni").is_equal(VETO)
			assert_bool(_factor(rec, F_ZONING).is_empty()).override_failure_message("yerine konan etken").is_true()
	assert_int(recorded).is_greater(0)
	for v in f.parcel_views(f.parcel_ids()):
		if v.decision != ParcelView.DECISION_NONE:
			assert_str(String(v.decision_code)).is_equal(UNPLANNED_CODE)
		assert_str(String(v.zone)).override_failure_message("plansız parselde placeholder imar görünmemeli") \
			.is_equal("")


func test_same_scenario_without_the_flag_builds_on_the_placeholder_zone() -> void:
	# Kontrol: bayrak kapalıyken eski davranış (placeholder konut imarıyla yatırım olur) sürer.
	var f := W.facade(S.regions({"F1": S.favorable(), "F2": S.favorable()}))
	f.advance(200)
	assert_int(_approvals(f)).override_failure_message("kontrol koşusu yatırım üretmeliydi").is_greater(0)


# --- Ölçüt 3: plan + yürürlük -> engel kalkar, karar getiri/talep/kapasiteye bağlı ---

func test_proposal_lifts_the_block_only_on_planned_parcels_and_the_reason_names_the_plan_command() -> void:
	var f := W.facade(_favorable())
	var planned := f.parcel_ids(S.R1).slice(0, 4)
	var result := f.submit_command(SimCommand.zoning_propose(planned, &"zone.mixed"))
	assert_bool(result.is_rejected()).is_false()
	f.advance(150)
	var built := 0
	for p in planned:
		var v := f.parcel_views(PackedInt64Array([p]))[0]
		assert_str(String(v.zone)).is_equal("zone.mixed")
		if v.development != ParcelView.DEVELOPMENT_VACANT:
			built += 1
	assert_int(built).override_failure_message("planlı elverişli parsellerden hiçbiri yatırım almadı").is_greater(0)
	var source_seen := false
	for p in planned:
		for rec: Dictionary in _records_since(f, int(p), PLAN_IN_FORCE_TICK):
			assert_str(String(rec["code"])).override_failure_message("planlı parselde plan engeli").is_not_equal(UNPLANNED_CODE)
			assert_bool(_factor(rec, F_UNPLANNED).is_empty()).is_true()
			var zoning := _factor(rec, F_ZONING)
			assert_int(zoning["value"]).is_equal(0)
			if String(zoning["source_ref"]) == "command.%d" % result.command_id:
				source_seen = true
	assert_bool(source_seen).override_failure_message("gerekçede plan komutu (source_ref) görünmeli").is_true()
	# plansız kalan parseller hâlâ boş ve plansız
	for p in f.parcel_ids():
		if not planned.has(p):
			assert_str(String(f.parcel_views(PackedInt64Array([p]))[0].development)).is_equal("vacant")


func test_plan_equal_to_the_template_placeholder_still_wakes_the_investor_after_the_attention_delay() -> void:
	# Şablondaki placeholder imar `zone.residential`: aynı kullanımı planlamak da "imar değişti" sayılır (periyodik tarama
	# kapalı: yalnız zorunlu dikkat yolu değerlendirir). Bayrak kapalıyken bu durum tetiklenmezdi.
	var f := W.facade(S.merge(_favorable(), {"decision": {"review_enabled": 0}}))
	var p := int(f.parcel_ids(S.R1)[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.residential"))
	f.advance(PLAN_IN_FORCE_TICK + 4)  # yürürlük + attention_delay_days (2) + pay
	var recs := _records_since(f, p, PLAN_IN_FORCE_TICK)
	assert_int(recs.size()).override_failure_message("plan yürürlüğe girdi ama yatırımcı bakmadı").is_equal(1)
	assert_str(String(recs[0]["code"])).is_not_equal(UNPLANNED_CODE)


func test_plan_with_no_demand_is_approved_by_nobody_and_declined_on_demand_not_on_zoning() -> void:
	# Olumsuz yol: plan var, kapasite bol, talep yok -> bina yok; neden talep/getiri (imar değil).
	var patch := S.merge(ENABLED, {"regions": {"defaults": {"initial_households": 0, "infra_capacity_units": 100000,
		"access_pm": 1000, "service_pm": 1000}}})
	var f := W.facade(patch)
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
	f.advance(200)
	assert_int(_approvals(f)).is_equal(0)
	var seen := 0
	for p in f.parcel_ids():
		for rec: Dictionary in _records(f, int(p)):
			seen += 1
			assert_bool(["demand_too_low", "return_too_low"].has(String(rec["code"]))) \
				.override_failure_message("beklenmeyen kod %s" % rec["code"]).is_true()
	assert_int(seen).is_greater(0)


# --- Ölçüt 4: plan var kapasite yok -> infra; ikisi de yok -> iki neden birlikte ---

func test_plan_without_capacity_is_declined_on_infrastructure_only() -> void:
	var patch := S.merge(ENABLED, S.regions({"F1": {"initial_households": 400, "infra_capacity_units": 0},
		"F2": S.favorable()}))
	var f := W.facade(patch)
	var p := int(f.parcel_ids(S.R1)[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.mixed"))
	f.advance(20)
	var recs := _records_since(f, p, PLAN_IN_FORCE_TICK)
	assert_int(recs.size()).is_equal(1)
	assert_str(String(recs[0]["code"])).is_equal("infrastructure_exhausted")
	assert_int(_factor(recs[0], F_INFRA)["value"]).is_equal(VETO)
	assert_int(_factor(recs[0], F_ZONING)["value"]).is_equal(0)


func test_no_plan_and_no_capacity_lists_both_causes_together() -> void:
	var patch := S.merge(ENABLED, S.regions({"F1": {"initial_households": 400, "infra_capacity_units": 0},
		"F2": S.favorable()}))
	var f := W.facade(patch)
	f.advance(120)
	var found := false
	for p in f.parcel_ids(S.R1):
		for rec: Dictionary in _records(f, int(p)):
			found = true
			assert_str(String(rec["code"])).is_equal(UNPLANNED_CODE)
			assert_int(_factor(rec, F_UNPLANNED)["value"]).is_equal(VETO)
			assert_int(_factor(rec, F_INFRA)["value"]) \
				.override_failure_message("kapasite eksikliği de listelenmeli").is_equal(VETO)
	assert_bool(found).is_true()


# --- Ölçüt 6: yapılı parsel imarını korur ---

func test_built_parcel_keeps_its_zoning_and_is_never_unplanned() -> void:
	var stock := ListStockSource.create([{"parcel_id": 1, "use": "residential", "units": 8, "owner": 0}])
	var h := W.handle(_favorable(), S.SEED, S.PER_REGION, stock)
	var f := h.facade
	f.advance(120)
	var v := f.parcel_views(PackedInt64Array([1]))[0]
	assert_str(String(v.development)).is_equal("built")
	assert_str(String(v.zone)).override_failure_message("yapılı parselin imarı boşaltılmamalı") \
		.is_equal("zone.residential")
	assert_int(_records(f, 1).size()).is_equal(0)
	assert_str(String(h.system.plan_state(f.game_state(), 1)["state"])).is_equal("existing")


# --- Plan durumu sorgusu (UI sözleşmesi) ---

func test_plan_state_query_walks_unplanned_proposed_planned() -> void:
	var h := W.handle(_favorable())
	var f := h.facade
	var p := int(f.parcel_ids(S.R1)[0])
	f.advance(1)
	var st := h.system.plan_state(f.game_state(), p)
	assert_str(String(st["state"])).is_equal("unplanned")
	var result := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p]), &"zone.mixed"))
	f.advance(1)  # komut uygulandı, yürürlük henüz yok
	st = h.system.plan_state(f.game_state(), p)
	assert_str(String(st["state"])).is_equal("proposed")
	assert_str(String(st["pending_zone"])).is_equal("zone.mixed")
	assert_int(st["due_tick"]).is_equal(f.current_tick() - 1 + 3)
	assert_str(String(st["source_ref"])).is_equal("command.%d" % result.command_id)
	f.advance(3)
	st = h.system.plan_state(f.game_state(), p)
	assert_str(String(st["state"])).is_equal("planned")
	assert_str(String(st["zone"])).is_equal("zone.mixed")


func test_plan_state_is_untracked_when_the_flag_is_off() -> void:
	var h := W.handle()
	h.facade.advance(1)
	assert_str(String(h.system.plan_state(h.facade.game_state(), 1)["state"])).is_equal("untracked")


# --- Önizleme: sim sayısıyla birebir ---

func test_preview_units_equal_the_units_the_investor_later_builds() -> void:
	var h := W.handle(_favorable())
	var f := h.facade
	f.advance(1)
	var ids := f.parcel_ids(S.R1).slice(0, 4)
	var preview := h.system.plan_preview(f.game_state(), ids, &"zone.residential", -1, -1)
	assert_bool(preview["ok"]).is_true()
	assert_int(preview["parcels"].size()).is_equal(4)
	f.submit_command(SimCommand.zoning_propose(ids, &"zone.residential"))
	f.advance(120)
	var checked := 0
	for entry: Dictionary in preview["parcels"]:
		var rec := EconomyQuery.parcel_record(f.game_state(), int(entry["id"]))
		if rec["stage"] == &"vacant":
			continue
		checked += 1
		assert_str(String(rec["use"])).is_equal(String(entry["use"]))
		assert_int(rec["units"]).override_failure_message("önizleme birimi gerçek birimden farklı").is_equal(entry["units"])
	assert_int(checked).override_failure_message("kıyaslanacak yapı çıkmadı").is_greater(0)


func test_preview_reports_capacity_load_and_density_scaling() -> void:
	var h := W.handle(_favorable())
	var f := h.facade
	f.advance(1)
	var ids := f.parcel_ids(S.R1).slice(0, 3)
	var base := h.system.plan_preview(f.game_state(), ids, &"zone.residential", -1, -1)
	var half := h.system.plan_preview(f.game_state(), ids, &"zone.residential", 500, -1)
	assert_int(base["total_units"]).is_equal(30)  # 3 parsel x 1800 m2 x 6/1000 x 1000/1000
	assert_int(half["total_units"]).is_equal(15)
	assert_int(base["total_infra_units"]).is_equal(30)
	var row: Dictionary = base["regions"][0]
	assert_str(String(row["code"])).is_equal("F1")
	assert_int(row["added_units"]).is_equal(30)
	assert_int(row["headroom_units"]).is_equal(row["capacity_units"] - row["load_units"])
	assert_bool(row["fits"]).is_true()
	var tight := W.handle(S.merge(ENABLED, S.regions({"F1": {"initial_households": 400, "infra_capacity_units": 5},
		"F2": S.favorable()})))
	tight.facade.advance(1)
	var no_fit := tight.system.plan_preview(tight.facade.game_state(), ids, &"zone.residential", -1, -1)
	assert_bool(no_fit["regions"][0]["fits"]).override_failure_message("5 birim kapasiteye 30 birim sığmaz").is_false()


func test_preview_of_unknown_land_use_or_parcel_is_not_ok() -> void:
	var h := W.handle(_favorable())
	h.facade.advance(1)
	assert_bool(h.system.plan_preview(h.facade.game_state(), PackedInt64Array([1]), &"zone.nope", -1, -1)["ok"]).is_false()
	assert_bool(h.system.plan_preview(h.facade.game_state(), PackedInt64Array([99999]), &"zone.mixed", -1, -1)["ok"]) \
		.is_false()


func test_preview_is_read_only() -> void:
	var h := W.handle(_favorable())
	var f := h.facade
	f.advance(5)
	var before := f.state_hash()
	h.system.plan_preview(f.game_state(), f.parcel_ids(), &"zone.mixed", -1, -1)
	h.system.plan_state(f.game_state(), 1)
	assert_str(f.state_hash()).is_equal(before)


# --- Ölçüt 7: determinizm + kayıt/yükleme ---

func _scripted(world_seed: int) -> SimFacadeImpl:
	var f := W.facade(_favorable(), world_seed)
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(S.R1).slice(0, 5), &"zone.mixed"))
	f.advance(40)
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(S.R2).slice(0, 3), &"zone.commercial"))
	return f


func test_same_seed_and_commands_give_the_same_hash_and_another_seed_differs() -> void:
	var a := _scripted(S.SEED)
	var b := _scripted(S.SEED)
	a.advance(100)
	b.advance(100)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	var c := _scripted(S.SEED + 1)
	c.advance(100)
	assert_str(c.state_hash()).is_not_equal(a.state_hash())


func test_save_load_midway_equals_the_uninterrupted_run() -> void:
	var straight := _scripted(S.SEED)
	straight.advance(120)
	var first := _scripted(S.SEED)
	first.advance(35)
	var bytes := first.export_save()
	var second := W.facade(_favorable(), S.SEED)
	var loaded := second.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	second.advance(85)
	assert_str(second.state_hash()).is_equal(straight.state_hash())


# --- Ölçüt 9 / CAN-03 ---

func test_plan_never_places_a_building_by_itself() -> void:
	var f := W.facade(S.merge(ENABLED, {"decision": {"review_enabled": 0},
		"regions": {"defaults": {"initial_households": 0, "infra_capacity_units": 100000}}}))
	f.submit_command(SimCommand.zoning_propose(f.parcel_ids(), &"zone.mixed"))
	f.advance(300)
	assert_bool(_vacant_all(f)).override_failure_message("plan tek başına bina yarattı (SIM-07)").is_true()
