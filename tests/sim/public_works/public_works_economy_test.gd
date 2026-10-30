extends GdUnitTestSuite
## T-042 adım 2 · Yolun ekonomik etkisi (D-009: bölgenin altyapı kapasitesi artar) ve yatırımcı gerekçesinde görünürlüğü
## (SIM-12). ÇİFT SENARYO, 5 tohum: iki bölge (A, B) ikisi de `infrastructure_exhausted` ile reddedilmiş; A'ya bağlı
## geçerli yol -> A'daki yatırım sim kurallarıyla onaylanır, gerekçede yol görünür; B reddedilmiş kalır. Bağlantısız yol
## reddedilir ve durum hiç komut verilmemiş koşuyla AYNIdır. Zorlama yok: kapasite artar, karar sim'in kuralıdır.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SEEDS: Array[int] = [11, 20261030, 3033, 40404, 505050]
const WARMUP := 40
const AFTER := 70
const INFRA := "reason.factor.infrastructure_capacity"


func _warm(world_seed: int) -> Dictionary:
	var run := P.setup(world_seed)
	(run["facade"] as SimFacadeImpl).advance(WARMUP)
	return run


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _developed(f: SimFacadeImpl, region: StringName) -> int:
	var n := 0
	for v in f.parcel_views(f.parcel_ids(region)):
		if v.development != &"vacant":
			n += 1
	return n


func _infra_factor(r: ReasonRecord) -> ReasonFactor:
	for fac in r.factors:
		if fac.name_key == StringName(INFRA):
			return fac
	return null


func _investor_reasons(f: SimFacadeImpl, v: ParcelView) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	for r in f.reasons_for(v.ref()):
		if r.decision_key == &"decision.investor.develop":
			out.append(r)
	return out


# --- Önkoşul: iki bölge de altyapı yüzünden reddedilmiş ---

func test_before_any_road_both_regions_are_declined_for_infrastructure() -> void:
	for world_seed in SEEDS:
		var f := _f(_warm(world_seed))
		for region in [P.CODE_A, P.CODE_B]:
			assert_int(_developed(f, region)).override_failure_message("tohum %d" % world_seed).is_equal(0)
			var codes := P.codes_of(f, region)
			assert_bool(codes.has(&"infrastructure_exhausted")) \
				.override_failure_message("tohum %d bölge %s: %s" % [world_seed, region, codes]).is_true()


# --- Çift senaryo ---

func test_road_connected_to_a_unblocks_a_and_the_reason_names_the_road_while_b_stays_declined() -> void:
	for world_seed in SEEDS:
		var run := _warm(world_seed)
		var f := _f(run)
		var r := f.submit_command(P.road(P.spur_a_cm()))
		assert_str(String(r.status)).is_equal("queued")
		f.advance(AFTER)
		var msg := "tohum %d" % world_seed
		assert_int(_developed(f, P.CODE_A)).override_failure_message(msg + " A hiç onaylanmadı").is_greater(0)
		assert_int(_developed(f, P.CODE_B)).override_failure_message(msg + " B değişti").is_equal(0)
		assert_bool(P.codes_of(f, P.CODE_B).has(&"infrastructure_exhausted")).override_failure_message(msg).is_true()
		# Gerekçede yol görünür: kapasite etkeni source_ref = yol komutu, değer pozitif (veto kalktı)
		var shown := 0
		for v in f.parcel_views(f.parcel_ids(P.CODE_A)):
			if v.decision != &"approved":
				continue
			var reasons := _investor_reasons(f, v)
			assert_int(reasons.size()).override_failure_message(msg).is_greater(0)
			var latest := reasons[reasons.size() - 1]
			assert_str(String(latest.outcome)).is_equal("positive")
			var fac := _infra_factor(latest)
			assert_object(fac).is_not_null()
			assert_str(String(fac.source_ref)).override_failure_message(msg).is_equal("command.1")
			assert_int(fac.value).is_greater(-1)
			assert_bool(latest.is_consistent()).is_true()
			shown += 1
		assert_int(shown).override_failure_message(msg).is_greater(0)


func test_the_same_road_for_b_unblocks_b_not_a() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	f.submit_command(P.road(P.spur_b_cm()))
	f.advance(AFTER)
	assert_int(_developed(f, P.CODE_B)).is_greater(0)
	assert_int(_developed(f, P.CODE_A)).is_equal(0)


func test_declined_reasons_of_other_regions_carry_no_road_reference() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(AFTER)
	for v in f.parcel_views(f.parcel_ids(P.CODE_B)):
		for r in _investor_reasons(f, v):
			var fac := _infra_factor(r)
			assert_str(String(fac.source_ref)).is_empty()


func test_a_road_changes_capacity_only_not_the_decision_rule() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	var before := EconomyQuery.region_stats(f.game_state(), run["handle"].config)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)  # komut tick'te uygulandı, değerlendirmeler henüz işlemedi
	var after := EconomyQuery.region_stats(f.game_state(), run["handle"].config)
	for k in before.size():
		var delta_cap: int = int(after[k]["infra_cap"]) - int(before[k]["infra_cap"])
		assert_int(delta_cap).is_equal(10 if before[k]["code"] == P.CODE_A else 0)


# --- Olumsuz: bağlantısız / geçersiz yol durumu değiştirmez ---

func test_a_rejected_road_leaves_the_run_identical_to_a_run_without_the_command() -> void:
	for world_seed in SEEDS:
		var with_cmd := _warm(world_seed)
		var without := _warm(world_seed)
		for bad in [P.road(P.detached_cm()), P.road(P.lake_cm()), P.road(P.spur_a_cm(), &"arterial")]:
			var r := _f(with_cmd).submit_command(bad)
			assert_bool(r.is_rejected()).is_true()
		_f(with_cmd).advance(AFTER)
		_f(without).advance(AFTER)
		assert_str(_f(with_cmd).state_hash()).override_failure_message("tohum %d" % world_seed) \
			.is_equal(_f(without).state_hash())
		assert_int(_developed(_f(with_cmd), P.CODE_A)).is_equal(0)


func test_a_road_in_the_other_region_does_not_unblock_a() -> void:
	var run := _warm(P.SEED)
	_f(run).submit_command(P.road(P.spur_b_cm()))
	_f(run).advance(AFTER)
	assert_int(_developed(_f(run), P.CODE_A)).is_equal(0)
	assert_bool(P.codes_of(_f(run), P.CODE_A).has(&"infrastructure_exhausted")).is_true()


# --- Geri alma: kapasite düşer, durma kuralı devreye girer ---

func test_undo_returns_capacity_and_the_existing_stall_rule_applies_to_projects_in_progress() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(30)  # onay + inşaata başlama
	assert_int(_developed(f, P.CODE_A)).is_greater(0)
	var cap_with_road := int(EconomyQuery.region_stats(f.game_state(), run["handle"].config)[0]["infra_cap"])
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	var cap_after := int(EconomyQuery.region_stats(f.game_state(), run["handle"].config)[0]["infra_cap"])
	assert_int(cap_with_road - cap_after).is_equal(10)
	f.advance(60)
	var totals := EconomyQuery.totals(f.game_state())
	assert_int(int(totals["stalls"])).override_failure_message("durma sayacı: %s" % totals).is_greater(0)


func test_undone_road_no_longer_unblocks_new_investments() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(AFTER)
	assert_int(_developed(f, P.CODE_A)).is_equal(0)


# --- Çıktı görünümü ---

func test_economy_outcome_exposes_capacity_and_the_part_that_came_from_roads() -> void:
	var run := _warm(P.SEED)
	var f := _f(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(2)
	var o := f.economy_outcome()
	assert_int(o.region(P.CODE_A).infra_capacity_units).is_equal(15)
	assert_int(o.region(P.CODE_A).infra_from_public_works_units).is_equal(10)
	assert_int(o.region(P.CODE_B).infra_capacity_units).is_equal(5)
	assert_int(o.region(P.CODE_B).infra_from_public_works_units).is_equal(0)
