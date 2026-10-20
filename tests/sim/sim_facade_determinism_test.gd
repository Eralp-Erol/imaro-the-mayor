extends SimTestBase
## T-027 ölçüt 4 · Facade seviyesinde determinizm ve kayıt/yükleme: aynı tohum + aynı komutlar = aynı hash; farklı
## tohum/komut = farklı hash; kare bağımsızlığı; kaydet -> yükle -> devam = kesintisiz koşu (hash + gözlenebilir).

const K_TICKS := 14
const M_TICKS := 23


## Test sistemi: günlük karar (kendi RNG akışı) -> gerekçe + `actor.decided` olayı (T-013'ün yapacağının iskeleti).
class DecidingSystem:
	extends SimSystem

	func system_id() -> StringName:
		return &"test_decider"

	func on_daily(state: GameState) -> void:
		var roll := state.rng.stream(&"test_decider").randi_range(0, 999)
		var id := state.record_reason(&"actor.investor.1", &"decision.investor.develop",
			[{"name": &"reason.factor.demand", "value": roll, "weight": 1000}], 500, &"",
			PackedStringArray(["parcel.1"]))
		SimEventLog.emit(state, &"actor.decided", &"event.investor.develop", PackedStringArray(["parcel.1"]), {},
			PackedInt64Array([id]), 0, &"actor.investor.1")


func _facade(world_seed: int = SEED) -> SimFacadeImpl:
	var systems: Array[SimSystem] = [DecidingSystem.new()]
	return SimFacadeImpl.create(world_seed, FacadeTestSupport.fixture_source(3), null, null, systems)


## Standart senaryo: komutlar belirli tick'lerde.
func _play(f: SimFacadeImpl, ticks: int, start: int = 0) -> void:
	for t in range(start, start + ticks):
		if t == 2:
			f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1, 2]), &"zone.mixed"))
		if t == 6:
			f.submit_command(SimCommand.zoning_propose(PackedInt64Array([3]), &"zone.green"))
		if t == 9:
			f.submit_command(SimCommand.zoning_propose(PackedInt64Array([99999]), &"zone.green"))  # reddedilir
		f.advance(1)


## Facade'ın gözlenebilir durumunun (snapshot/olay/gerekçe/parsel) hash'i.
func _obs(f: SimFacade) -> String:
	return assert_hash(StateHash.of(SimContractChecks.observable_state(f)))


func test_same_seed_and_commands_give_same_hashes() -> void:
	var a := _facade()
	var b := _facade()
	_play(a, K_TICKS + M_TICKS)
	_play(b, K_TICKS + M_TICKS)
	assert_str(assert_hash(a.state_hash())).is_equal(b.state_hash())
	assert_str(_obs(a)).is_equal(_obs(b))
	assert_array(SimContractChecks.check_facade(a)).is_empty()
	assert_int(a.reason(1).id).is_equal(1)


func test_different_seed_or_commands_give_different_hashes() -> void:
	var base := _facade()
	_play(base, K_TICKS)
	var other_seed := _facade(SEED + 1)
	_play(other_seed, K_TICKS)
	assert_str(base.state_hash()).override_failure_message("tohum kullanılmıyor").is_not_equal(other_seed.state_hash())
	var no_commands := _facade()
	no_commands.advance(K_TICKS)
	assert_str(base.state_hash()).is_not_equal(no_commands.state_hash())
	assert_str(_obs(base)).is_not_equal(_obs(no_commands))
	var other_command := _facade()
	for t in K_TICKS:
		if t == 2:
			other_command.submit_command(SimCommand.zoning_propose(PackedInt64Array([1, 2]), &"zone.commercial"))
		other_command.advance(1)
	assert_str(base.state_hash()).is_not_equal(other_command.state_hash())


func test_hash_is_independent_of_frame_slicing_at_the_same_game_time() -> void:
	var frame_plans: Array = [
		[10_000_000],
		[1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000],
		[3_333_333, 3_333_333, 3_333_334],
		[16_667, 33_333, 250_000, 1_700_000, 8_000_000],
	]
	var hashes: Array[String] = []
	for plan: Array in frame_plans:
		var f := _facade()
		f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
		var ticks := 0
		for usec: int in plan:
			ticks += f.drive_usec(usec)
		assert_int(ticks).is_equal(10)
		hashes.append(assert_hash(f.state_hash()))
	for h in hashes:
		assert_str(h).is_equal(hashes[0])


func test_save_load_continue_equals_uninterrupted_run_at_facade_level() -> void:
	var straight := _facade()
	_play(straight, K_TICKS + M_TICKS)

	var first := _facade()
	_play(first, K_TICKS)
	var bytes := first.export_save()
	assert_int(bytes.size()).is_greater(0)
	var restored := _facade()  # taze kurulum: aynı kaynak, aynı sistemler
	var result := restored.import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(restored.state_hash()).is_equal(first.state_hash())
	assert_str(_obs(restored)).is_equal(_obs(first))
	_play(restored, M_TICKS, K_TICKS)

	assert_str(restored.state_hash()).is_equal(straight.state_hash())
	assert_str(_obs(restored)).override_failure_message("gözlenebilir durum (snapshot/olay/gerekçe/parsel)") \
		.is_equal(_obs(straight))
	assert_int(restored.current_tick()).is_equal(K_TICKS + M_TICKS)
	assert_array(SimContractChecks.check_facade(restored)).is_empty()


func test_queued_command_survives_save_and_applies_after_load() -> void:
	var f := _facade()
	f.advance(3)
	assert_int(f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed")).command_id).is_equal(1)
	var bytes := f.export_save()  # komut kuyrukta, henüz uygulanmadı
	var restored := _facade()
	assert_bool(restored.import_save(bytes).ok).is_true()
	assert_int(restored.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.green")).command_id) \
		.override_failure_message("komut kimliği kayıttan sürer").is_equal(2)
	restored.advance(1)
	var applied := restored.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == &"command.applied")
	assert_array(applied.map(func(e: SimEvent) -> int: return e.command_id)).is_equal([1, 2])


func test_import_failures_keep_the_current_state() -> void:
	var f := _facade()
	_play(f, 5)
	var h := f.state_hash()
	var junk := f.import_save(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]))
	assert_bool(junk.ok).is_false()
	assert_str(junk.message).is_not_empty()
	assert_bool(f.import_save(PackedByteArray()).ok).is_false()
	assert_str(f.state_hash()).override_failure_message("başarısız yükleme durumu bozmamalı").is_equal(h)


func test_import_of_a_save_from_another_world_is_rejected() -> void:
	var f := _facade()
	_play(f, 5)
	var other_source := FacadeTestSupport.fixture_source(2)  # farklı parsel sayısı = farklı dünya
	var other := SimFacadeImpl.create(SEED, other_source)
	other.advance(4)
	var h := f.state_hash()
	var result := f.import_save(other.export_save())
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("world_mismatch")
	assert_object(result.state).is_null()
	assert_str(f.state_hash()).is_equal(h)
	var renamed := SimFacadeImpl.create(SEED, ListParcelSource.create(&"another.world",
		FacadeTestSupport.fixture_views(FacadeTestSupport.fixture_world(), 3)))
	assert_str(String(f.import_save(renamed.export_save()).error_code)).is_equal("world_mismatch")


func test_old_version_save_is_rejected_by_the_facade() -> void:
	var f := _facade()
	var envelope: Dictionary = bytes_to_var(f.export_save())
	envelope["version"] = 1
	var result := f.import_save(var_to_bytes(envelope))
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("version_too_old")


func test_load_keeps_speed_and_campaign_outside_sim_state() -> void:
	var f := _facade()
	f.campaign_id = &"campaign.a"
	f.set_speed(SimFacade.SPEED_FASTEST)
	var bytes := f.export_save()
	var restored := _facade()
	restored.campaign_id = &"campaign.b"
	restored.set_speed(SimFacade.SPEED_FAST)
	assert_bool(restored.import_save(bytes).ok).is_true()
	assert_int(restored.speed()).override_failure_message("hız oturumundur, kayıtta değil").is_equal(SimFacade.SPEED_FAST)
	assert_str(String(restored.snapshot().scenario_id)).is_equal("campaign.b")
	assert_str(restored.state_hash()).is_equal(f.state_hash())
