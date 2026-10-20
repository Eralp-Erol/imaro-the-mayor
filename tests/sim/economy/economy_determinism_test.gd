extends SimTestBase
## T-013 ölçüt 7 · Determinizm ve kayıt: aynı tohum + aynı komutlar = aynı hash; farklı tohum/komut = farklı hash;
## kare bağımsızlığı; kaydet -> yükle -> devam = kesintisiz koşu (facade seviyesinde, yolda proje varken); bozuk ekonomi
## kaydı anlaşılır hatayla reddedilir. Senaryo otonom büyüme + komutlar + durma/devam içerir.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const K_TICKS := 70
const M_TICKS := 90


func _patch() -> Dictionary:
	return S.regions({"F1": S.favorable(), "F2": {"initial_households": 60, "infra_capacity_units": 40}})


## Standart senaryo: otonom tarama AÇIK; komutlar belirli tick'lerde; 40. günde F1 altyapısı düşer (durma), 55'te döner.
func _play(h: EconomyHandle, from_tick: int, ticks: int) -> void:
	var f := h.facade
	for t in range(from_tick, from_tick + ticks):
		if t == 2:
			f.submit_command(SimCommand.zoning_propose(f.parcel_ids(S.R1).slice(0, 3), &"zone.mixed"))
		if t == 8:
			f.submit_command(SimCommand.make(&"zoning.propose", {"parcel_ids": f.parcel_ids(S.R2).slice(0, 2),
				"land_use": &"zone.commercial", "density": 2000, "max_height_m": 9}))
		if t == 12:
			f.submit_command(SimCommand.zoning_propose(PackedInt64Array([424242]), &"zone.mixed"))  # reddedilir
		if t == 40:
			var cap: PackedInt64Array = W.data(f)["regions"]["infra_cap"]
			cap[0] = 0
		if t == 55:
			var cap2: PackedInt64Array = W.data(f)["regions"]["infra_cap"]
			cap2[0] = 2000
		f.advance(1)


func _obs(f: SimFacade) -> String:
	return assert_hash(StateHash.of(SimContractChecks.observable_state(f)))


func test_same_seed_and_commands_give_identical_hash_and_observable_state() -> void:
	var a := W.handle(_patch())
	var b := W.handle(_patch())
	_play(a, 0, K_TICKS + M_TICKS)
	_play(b, 0, K_TICKS + M_TICKS)
	assert_str(assert_hash(a.facade.state_hash())).is_equal(b.facade.state_hash())
	assert_str(_obs(a.facade)).is_equal(_obs(b.facade))
	assert_array(SimContractChecks.check_facade(a.facade)).is_empty()
	var totals := EconomyQuery.totals(a.facade.game_state())
	assert_int(totals["approvals"]).override_failure_message("senaryo yatırım üretmeli").is_greater(0)
	assert_int(totals["stalls"]).override_failure_message("senaryo durma üretmeli").is_greater(0)


func test_different_seed_or_commands_give_different_hashes() -> void:
	var base := W.handle(_patch())
	var other_seed := W.handle(_patch(), S.SEED + 1)
	var other_commands := W.handle(_patch())
	_play(base, 0, K_TICKS)
	_play(other_seed, 0, K_TICKS)
	for t in K_TICKS:
		if t == 3:
			other_commands.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.green"))
		other_commands.facade.advance(1)
	assert_str(other_seed.facade.state_hash()) \
		.override_failure_message("tohum kullanılmıyor") \
		.is_not_equal(base.facade.state_hash())
	assert_str(other_commands.facade.state_hash()).is_not_equal(base.facade.state_hash())


func test_frame_partition_does_not_change_the_result() -> void:
	var a := W.handle(_patch())
	var b := W.handle(_patch())
	a.facade.set_speed(3)
	b.facade.set_speed(3)
	a.facade.submit_command(SimCommand.zoning_propose(a.facade.parcel_ids(S.R1).slice(0, 3), &"zone.mixed"))
	b.facade.submit_command(SimCommand.zoning_propose(b.facade.parcel_ids(S.R1).slice(0, 3), &"zone.mixed"))
	for i in 400:
		a.facade.drive_usec(10_000)  # 400 x 10 ms
	for i in 8:
		b.facade.drive_usec(500_000)  # 8 x 500 ms
	assert_int(a.facade.current_tick()).is_equal(64)
	assert_int(b.facade.current_tick()).is_equal(64)
	assert_str(assert_hash(a.facade.state_hash())).is_equal(b.facade.state_hash())


func test_save_load_continue_equals_the_uninterrupted_run_with_projects_in_flight() -> void:
	var whole := W.handle(_patch())
	_play(whole, 0, K_TICKS + M_TICKS)
	var first := W.handle(_patch())
	_play(first, 0, K_TICKS)
	var d := W.data(first.facade)
	var in_flight := 0
	for s: int in d["stage"]:
		if s != EconomyState.STAGE_VACANT and s != EconomyState.STAGE_BUILT:
			in_flight += 1
	assert_int(in_flight).override_failure_message("kayıt anında yolda proje olmalı (planned/inşaat/durmuş)").is_greater(0)
	var bytes := first.facade.export_save()
	assert_int(bytes.size()).is_greater(0)
	var resumed := W.handle(_patch())
	var loaded := resumed.facade.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(resumed.facade.state_hash()).override_failure_message("yükleme hash'i").is_equal(first.facade.state_hash())
	_play(resumed, K_TICKS, M_TICKS)
	assert_str(assert_hash(resumed.facade.state_hash())) \
		.override_failure_message("kaydet->yükle->devam") \
		.is_equal(whole.facade.state_hash())
	assert_str(_obs(resumed.facade)).is_equal(_obs(whole.facade))


func test_sparse_dictionaries_survive_the_save_round_trip_with_integer_keys() -> void:
	var h := W.handle(S.merge(_patch(), {"decision": {"review_enabled": 0}}))
	h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(S.R1).slice(0, 2), &"zone.mixed"))
	h.facade.advance(4)  # imar yürürlükte, dikkat kuyruğunda bekleyen değerlendirme var
	var d := W.data(h.facade)
	assert_int((d["attention"] as Dictionary).size()).is_greater(0)
	var other := W.handle(S.merge(_patch(), {"decision": {"review_enabled": 0}}))
	assert_bool(other.facade.import_save(h.facade.export_save()).ok).is_true()
	var loaded := W.data(other.facade)
	for key: Variant in loaded["attention"]:
		assert_int(typeof(key)).override_failure_message("anahtar int kalmalı").is_equal(TYPE_INT)
	assert_dict(loaded["attention"]).is_equal(d["attention"])
	assert_dict(loaded["zone_seen"]).is_equal(d["zone_seen"])
	other.facade.advance(3)
	h.facade.advance(3)
	assert_str(other.facade.state_hash()).is_equal(h.facade.state_hash())


func test_loading_a_save_with_a_damaged_economy_section_is_rejected_with_a_clear_message() -> void:
	var h := W.handle(_patch())
	_play(h, 0, 5)
	var state := h.facade.game_state()
	var damaged := GameState.from_dict(state.to_dict())
	(damaged.systems["economy"] as Dictionary).erase("stage")
	var bad := SimSave.encode(damaged)
	var target := W.handle(_patch())
	var result := target.facade.import_save(bad)
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("corrupt")
	assert_str(result.message).contains("economy")
	assert_int(target.facade.current_tick()).override_failure_message("başarısız yüklemede durum korunur").is_equal(0)
	# Parsel sayısı uyuşmayan ekonomi bölümü
	var short := GameState.from_dict(state.to_dict())
	var eco: Dictionary = short.systems["economy"]
	eco["stage"] = (eco["stage"] as PackedByteArray).slice(0, 2)
	var result2 := target.facade.import_save(SimSave.encode(short))
	assert_bool(result2.ok).is_false()
	assert_str(result2.message).contains("economy")


func test_a_save_from_a_different_world_is_still_rejected_with_the_economy_installed() -> void:
	var h := W.handle(_patch())
	_play(h, 0, 5)
	var other := W.handle(_patch(), S.SEED, 4)  # farklı parsel sayısı
	var result := other.facade.import_save(h.facade.export_save())
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("world_mismatch")
