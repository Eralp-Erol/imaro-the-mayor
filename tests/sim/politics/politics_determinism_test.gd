extends PoliticsTestBase
## T-017 ölçüt 6 · Determinizm ve kayıt: aynı tohum + aynı komut = aynı durum hash'i ve gözlenebilir akış; ekonomi +
## aktör + siyaset birlikte; farklı tohum/komut farklı sonuç (SIM-10); kare bağımsızlığı; kaydet -> yükle -> devam =
## kesintisiz koşu; `ActorSystem` kendi sistemlerinden ÖNCE kayıtlı; ReasonLog hacmi sınırlı.

const K_TICKS := 70
const M_TICKS := 90


func _play(h: PoliticsHandle, ticks: int, start: int = 0) -> void:
	for t in range(start, start + ticks):
		if t == 1:
			h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
		if t == 40:
			Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": 999, "option_id": "listen"})
		h.facade.advance(1)


func _stress(seed_value: int = SEED) -> PoliticsHandle:
	return handle(E.regions(STRESS), 14, seed_value, func(f: Dictionary) -> void:
		f["council"]["requires_council"]["zoning.propose"] = false)


func _obs(h: PoliticsHandle) -> String:
	var hash := StateHash.of(SimContractChecks.observable_state(h.facade))
	assert_int(hash.length()).is_equal(64)
	return hash


func test_same_seed_and_commands_give_identical_state_and_observable_stream() -> void:
	var a := _stress()
	var b := _stress()
	_play(a, K_TICKS + M_TICKS)
	_play(b, K_TICKS + M_TICKS)
	assert_str(a.state().state_hash()).is_equal(b.state().state_hash())
	assert_str(_obs(a)).is_equal(_obs(b))
	assert_int(pol(a)["counters"]["reason_records"]).override_failure_message("ölü senaryo").is_greater(5)
	assert_int(a.facade.last_event_seq()).is_equal(b.facade.last_event_seq())
	assert_array(SimContractChecks.check_facade(a.facade)).is_empty()


func test_politics_state_is_part_of_the_hash() -> void:
	var a := _stress()
	var b := _stress()
	_play(a, 40)
	_play(b, 40)
	var before := a.state().state_hash()
	assert_str(before).is_equal(b.state().state_hash())
	pol(a)["blocs"][BLOC_HOUSED]["G"] = int(pol(a)["blocs"][BLOC_HOUSED]["G"]) + 1
	assert_str(a.state().state_hash()).override_failure_message("kesim durumu hash'te değil").is_not_equal(before)
	var c := _stress()
	_play(c, 40)
	pol(c)["council"]["friction_adjust"] = 1
	assert_str(c.state().state_hash()).is_not_equal(before)
	var d := _stress()
	_play(d, 40)
	ActorStore.actor_ref(d.state(), BLOC_HOUSED)["state"]["grievances"]["mobility"] = 3
	assert_str(d.state().state_hash()).override_failure_message("kesim defteri hash'te değil").is_not_equal(before)


func test_different_seed_or_commands_give_different_outcomes() -> void:
	var base := _stress()
	var other_seed := _stress(SEED + 1)
	var quiet := _stress()
	_play(base, K_TICKS)
	_play(other_seed, K_TICKS)
	quiet.facade.advance(K_TICKS)  # komutsuz
	assert_str(base.state().state_hash()).is_not_equal(other_seed.state().state_hash())
	assert_str(base.state().state_hash()).is_not_equal(quiet.state().state_hash())
	var factors_of := func(r: Dictionary) -> Array: return r["factors"]
	var base_noise := reasons_of(base, "decision.bloc.react.petition").map(factors_of)
	var seed_noise := reasons_of(other_seed, "decision.bloc.react.petition").map(factors_of)
	assert_bool(base_noise.is_empty()).override_failure_message("ölü senaryo").is_false()
	assert_bool(base_noise == seed_noise).override_failure_message("tohum karar gürültüsünü değiştirmeli").is_false()


func test_two_command_scripts_from_the_same_seed_diverge_in_political_state() -> void:
	var dense := _stress()
	var green := _stress()
	dense.facade.submit_command(SimCommand.zoning_propose(dense.facade.parcel_ids(), &"zone.mixed"))
	green.facade.submit_command(SimCommand.zoning_propose(green.facade.parcel_ids(), &"zone.green"))
	tick(dense, 200)
	tick(green, 200)
	var dense_reactions := dense.facade.snapshot().group_reactions.map(
		func(g: GroupReactionView) -> String: return "%s:%d" % [g.reaction, g.intensity])
	var green_reactions := green.facade.snapshot().group_reactions.map(
		func(g: GroupReactionView) -> String: return "%s:%d" % [g.reaction, g.intensity])
	assert_array(dense_reactions) \
		.override_failure_message("farklı politika farklı tepki üretmeli").is_not_equal(green_reactions)
	assert_int(pol(dense)["blocs"][BLOC_HOUSED]["G"]).is_greater(pol(green)["blocs"][BLOC_HOUSED]["G"])


func test_hash_is_independent_of_frame_slicing_at_the_same_game_time() -> void:
	var plans: Array = [
		[10_000_000],
		[1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000, 1_000_000],
		[16_667, 33_333, 250_000, 1_700_000, 8_000_000],
	]
	var hashes: Array[String] = []
	for plan: Array in plans:
		var h := _stress()
		h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
		var ticks := 0
		for usec: int in plan:
			ticks += h.facade.drive_usec(usec)
		assert_int(ticks).is_equal(10)
		hashes.append(h.state().state_hash())
	for digest in hashes:
		assert_str(digest).is_equal(hashes[0])


func test_save_load_continue_equals_an_uninterrupted_run() -> void:
	var straight := _stress()
	_play(straight, K_TICKS + M_TICKS)
	var first := _stress()
	_play(first, K_TICKS)
	assert_int(pol(first)["counters"]["reason_records"]) \
		.override_failure_message("kayıtta siyasi durum olmalı").is_greater(0)
	var bytes := first.facade.export_save()
	assert_int(bytes.size()).is_greater(0)
	var restored := _stress()
	var result := restored.facade.import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(restored.state().state_hash()).is_equal(first.state().state_hash())
	assert_str(_obs(restored)).is_equal(_obs(first))
	_play(restored, M_TICKS, K_TICKS)
	assert_str(restored.state().state_hash()).is_equal(straight.state().state_hash())
	assert_str(_obs(restored)).is_equal(_obs(straight))
	assert_array(SimContractChecks.check_facade(restored.facade)).is_empty()


func test_save_load_with_a_pending_council_vote_and_open_agenda_item_continues_identically() -> void:
	var edit := func(f: Dictionary) -> void:
		f["council"]["requires_council"]["zoning.propose"] = true
		f["templates"]["pe-04"]["weight"] = 1000
		f["templates"]["pe-04"]["hard"] = []
		for driver: Dictionary in f["templates"]["pe-04"]["drivers"]:
			driver["lo"] = -100000
			driver["hi"] = -99999
	var make := func() -> PoliticsHandle:
		return handle(E.regions(STRESS), 14, SEED, edit)
	var straight: PoliticsHandle = make.call()
	var split: PoliticsHandle = make.call()
	for h in [straight, split]:
		h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
		h.facade.advance(8)
		pol(h)["media"]["last_tick"] = 8
		pol(h)["media"]["last"] = {"tick": 8, "newsworthiness": 900, "lean": 400, "fact": 500}
		h.facade.advance(4)  # 12. gün: oylama (14. gün) bekliyor
	assert_int(pol(split)["council"]["votes"].size()).is_equal(1)
	assert_str(pol(split)["council"]["votes"][0]["status"]).override_failure_message("kayıt anında oylama bekliyor") \
		.is_equal("pending")
	assert_int(PoliticsQuery.agenda(split.state(), split.context).size()).is_greater(0)
	var restored: PoliticsHandle = make.call()
	assert_bool(restored.facade.import_save(split.facade.export_save()).ok).is_true()
	straight.facade.advance(60)
	restored.facade.advance(60)
	assert_str(restored.state().state_hash()).is_equal(straight.state().state_hash())
	assert_str(pol(restored)["council"]["votes"][0]["status"]).is_not_equal("pending")


func test_actor_system_is_registered_before_the_political_systems_that_use_it() -> void:
	var h := handle()
	var order: Array[String] = []
	for system: SimSystem in h.facade.simulation()._systems:
		order.append(String(system.system_id()))
	assert_array(order).is_equal(["parcels", "economy", "actors", "politics"])
	var state := h.state()
	assert_bool(ActorStore.is_initialized(state)).is_true()
	assert_bool(PoliticsState.is_initialized(state)).is_true()


func test_sim_state_holds_only_plain_serializable_values() -> void:
	var h := _stress()
	_play(h, 100)
	assert_str(StateHash.of(h.state().systems)) \
		.override_failure_message("durum hash'lenemiyor (desteksiz tür)").is_not_empty()
	assert_str(StateHash.of(h.state().to_dict())).is_not_empty()


func test_reason_volume_stays_bounded_over_two_game_years() -> void:
	var h := _stress()
	_play(h, 730)
	var politics_records: int = pol(h)["counters"]["reason_records"]
	assert_int(politics_records).override_failure_message("siyasi gerekçe sayısı (2 oyun yılı)").is_less(400)
	assert_int(politics_records).is_greater(10)
	assert_float(float(politics_records) / 730.0).override_failure_message("tick başına siyasi gerekçe").is_less(0.5)
	assert_int(pol(h)["counters"]["scans"]).is_equal(730 / 7)
