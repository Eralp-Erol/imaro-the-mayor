extends GdUnitTestSuite
## T-043B (sim yarısı) · Öncelik kuyruğunun durum sözleşmesi: bayrak/kuyruk kapalıyken eski davranış BİT-EŞİT (t0,
## yolsuz/
## plansız koşu, altınlar), yollu koşu tekrar oynatmada bit-eşit, kayıt/yükleme eşit, kuyruk yalnız ilk tetikte
## yaratılır
## (kayıt sürümü 1 -> 2), eski (sürüm 1) kayıt yüklenir ve sürer, CAN-03 (kuyruk bina yaratmaz, yalnız bakışı öne
## çeker).

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const OFF := {"decision": {"priority_review_enabled": 0}}
const TAIL := 90


## Standart betik: plan (yakın 6 parsel) -> 40 gün -> yol -> `TAIL` gün.
func _scripted(world_seed: int, extra: Dictionary = {}) -> SimFacadeImpl:
	var run := E.setup(extra, world_seed)
	var f := E.f(run)
	E.plan(f, [1, 2, 3, 4, 5, 6])
	f.advance(40)
	E.road_a(f)
	f.advance(TAIL)
	return f


func _economy_section(bytes: PackedByteArray) -> Dictionary:
	return bytes_to_var(bytes)["state"]["systems"]["economy"]


# --- Kapalıyken eski davranış bit-eşit ---

func test_t0_hash_does_not_depend_on_the_priority_flag() -> void:
	var on := E.f(E.setup())
	var off := E.f(E.setup(OFF))
	assert_str(on.state_hash()).is_equal(off.state_hash())


func test_runs_without_a_road_are_bit_equal_with_the_queue_on_or_off() -> void:
	# Yolsuz: ne tetikleyici ne bağlı parsel. Plansız koşu ve yalnız-plan koşusu kuyruk açıkken de aynı hash'i verir.
	var plans: Array = [[], [1, 2, 3]]
	for plan: Array in plans:
		var ids: Array[int] = []
		ids.assign(plan)
		var hashes: Array[String] = []
		for extra: Dictionary in [{}, OFF]:
			var f := E.f(E.setup(extra))
			if not ids.is_empty():
				E.plan(f, ids)
			f.advance(120)
			hashes.append(f.state_hash())
			assert_bool(E.eco(f).has("priority")).is_false()
			assert_int(int(E.eco(f)["version"])).override_failure_message("kuyruk yaratılmadı: sürüm 1 kalmalı").is_equal(1)
		assert_str(hashes[0]).override_failure_message("plan=%s" % [ids]).is_equal(hashes[1])


func test_with_the_unplanned_flag_off_the_queue_is_inert_even_with_road_and_plan() -> void:
	var inert := {"decision": {"unplanned_land_enabled": 0}}
	var a := _scripted(E.P.SEED, inert)
	var b := _scripted(E.P.SEED, E.S.merge(inert, OFF))
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_bool(E.eco(a).has("priority")).is_false()


func test_a_road_alone_far_from_planned_land_leaves_the_run_identical_to_queue_off() -> void:
	var hashes: Array[String] = []
	for extra: Dictionary in [{}, OFF]:
		var f := E.f(E.setup(extra))
		E.plan(f, E.FAR_A)
		f.advance(30)
		E.road_a(f)
		f.advance(60)
		hashes.append(f.state_hash())
	assert_str(hashes[0]).is_equal(hashes[1])


# --- Yollu koşu: tekrar oynatma, tohum, kayıt/yükleme ---

func test_same_seed_and_commands_replay_bit_equal_and_another_seed_differs() -> void:
	var a := _scripted(E.P.SEED)
	var b := _scripted(E.P.SEED)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_bool(E.eco(a).has("priority")).override_failure_message("kuyruk hiç kurulmadı: senaryo anlamsız").is_true()
	assert_str(_scripted(E.P.SEED + 1).state_hash()).is_not_equal(a.state_hash())


func test_the_queue_changes_the_run_compared_to_queue_off_when_a_road_follows_a_plan() -> void:
	assert_str(_scripted(E.P.SEED).state_hash()).is_not_equal(_scripted(E.P.SEED, OFF).state_hash())


func test_save_and_load_inside_the_queue_window_continue_to_the_uninterrupted_hash() -> void:
	var straight := _scripted(E.P.SEED)
	for cut in [1, 2, 3, 6]:  # kuyruk kuruldu / vade / dağıtım sürerken
		var run := E.setup({}, E.P.SEED)
		var f := E.f(run)
		E.plan(f, [1, 2, 3, 4, 5, 6])
		f.advance(40)
		E.road_a(f)
		f.advance(cut)
		var bytes := f.export_save()
		var fresh := E.f(E.setup({}, E.P.SEED))  # yeni oyun + taze ağ; kayıt yolu ağa işler
		var loaded := fresh.import_save(bytes)
		assert_bool(loaded.ok).override_failure_message("kesim %d: %s" % [cut, loaded.message]).is_true()
		fresh.advance(TAIL - cut)
		assert_str(fresh.state_hash()).override_failure_message("kesim %d" % cut).is_equal(straight.state_hash())


# --- Kayıt sürümü ve eski kayıt ---

func test_queue_is_created_at_the_first_trigger_only_and_raises_the_section_version() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, [1, 2, 3, 4, 5, 6])
	f.advance(40)
	assert_int(int(_economy_section(f.export_save())["version"])).is_equal(1)
	assert_bool(_economy_section(f.export_save()).has("priority")).is_false()
	E.road_a(f)
	f.advance(1)
	var section := _economy_section(f.export_save())
	assert_int(int(section["version"])).is_equal(2)
	assert_bool(section.has("priority") and section.has("priority_cmd")).is_true()
	assert_str(EconomyState.validate_data(section)).is_empty()


func test_a_version_1_save_loads_and_the_first_trigger_after_loading_upgrades_it() -> void:
	var first := E.f(E.setup())
	E.plan(first, [1, 2, 3, 4, 5, 6])
	first.advance(40)
	var bytes := first.export_save()  # sürüm 1, kuyruk yok (kuyruğu bilmeyen eski kayıtla aynı düzen)
	var old := _economy_section(bytes)
	assert_int(int(old["version"])).is_equal(1)
	assert_bool(old.has("priority")).is_false()
	var fresh := E.f(E.setup())
	var loaded := fresh.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	E.road_a(fresh)
	fresh.advance(TAIL)
	assert_int(int(E.eco(fresh)["version"])).is_equal(2)
	var straight := _scripted(E.P.SEED)
	assert_str(fresh.state_hash()).override_failure_message("eski kayıttan sürülen koşu kesintisizle aynı olmalı") \
		.is_equal(straight.state_hash())


func test_validate_data_accepts_versions_1_and_2_and_rejects_inconsistent_priority_data() -> void:
	var f := E.f(E.setup())
	E.plan(f, [1, 2, 3, 4, 5, 6])
	f.advance(40)
	E.road_a(f)
	f.advance(1)
	var good := _economy_section(f.export_save())
	assert_str(EconomyState.validate_data(good)).is_empty()
	var v3 := good.duplicate(true)
	v3["version"] = 3
	assert_str(EconomyState.validate_data(v3)).is_not_empty()
	var v1_with_queue := good.duplicate(true)
	v1_with_queue["version"] = 1
	assert_str(EconomyState.validate_data(v1_with_queue)) \
		.override_failure_message("sürüm 1 kuyruk taşıyamaz").is_not_empty()
	var half := good.duplicate(true)
	half.erase("priority_cmd")
	assert_str(EconomyState.validate_data(half)).is_not_empty()
	var bad_type := good.duplicate(true)
	bad_type["priority"] = []
	assert_str(EconomyState.validate_data(bad_type)).is_not_empty()


# --- CAN-03 / SIM-07 ---

func test_the_queue_never_creates_a_building_without_an_investor_decision_record() -> void:
	var f := _scripted(E.P.SEED)
	var developed := 0
	for v in f.parcel_views(f.parcel_ids()):
		if v.development == ParcelView.DEVELOPMENT_VACANT:
			continue
		developed += 1
		assert_bool(v.decision == ParcelView.DECISION_APPROVED and v.decision_reason_id > 0) \
			.override_failure_message("parsel %d: karar kaydı yok" % v.id).is_true()
		var reasons := f.reasons_for(v.ref())
		assert_bool(reasons.any(func(r: ReasonRecord) -> bool: return r.decision_key == &"decision.investor.develop")) \
			.is_true()
	assert_int(developed).is_greater(0)
	for v in f.parcel_views(E.FAR_A):
		assert_str(String(v.development)).override_failure_message("uzak/plansız parselde bina").is_equal("vacant")
