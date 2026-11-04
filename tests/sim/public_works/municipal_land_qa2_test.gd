extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## T-066 bağımsız QA turu 2 (D-018, CAN-03): karışık/yinelenen kimlik, aynı tick çift teklif, bekleyen planın üstüne
## yol, meclis yolunda kaydet/yükle, yanlış-pozitif taraması, GERİ AL/yıkım etkileşimi, ikinci döngü ve geri sarma,
## bozma biçimleri, ekonomi (bina yok; yalnız yatırımcı kararı), determinizm. Uygulamaya dokunmaz.

const SECOND_ROAD: Array[int] = [174000, 110000, 190000, 120000]
const WHY_STANDING := "municipal_land.road_still_standing"
const WHY_NOT_AVAILABLE := "municipal_land.not_available"
const WHY_PENDING := "municipal_land.plan_pending"
const WHY_WORLD := "municipal_land.world_unavailable"
const SNAP_KEYS: Array[String] = ["sim", "net", "graph", "graph_version", "ops", "parcels", "revision"]
## Başarısız yüklemede ağ içeriği eski haline döner; yalnız tek yönlü sürüm sayaçları ilerleyebilir.
const LOAD_KEYS: Array[String] = ["sim", "net", "graph", "ops", "parcels"]


# --- yardımcılar ---

func _qa_net(run: Dictionary) -> WorldNetwork:
	return run["net"]


func _qa_snap(run: Dictionary) -> Dictionary:
	var net := _qa_net(run)
	return {"sim": _land_f(run).state_hash(), "net": net.state_hash(), "graph": net.graph_hash(),
		"graph_version": net.graph_version, "ops": net.delta.ops.size(), "parcels": net.parcels.size(),
		"revision": net.parcel_revision}


func _qa_assert_same(run: Dictionary, before: Dictionary, label: String) -> void:
	var now := _qa_snap(run)
	for key in SNAP_KEYS:
		assert_that(now[key]).override_failure_message("%s: %s değişti" % [label, key]).is_equal(before[key])


func _qa_econ(run: Dictionary, id: int) -> Dictionary:
	var d := EconomyState.data(_land_f(run).game_state())
	var i := EconomyState.index_of(d, id)
	return {"stage": int(d["stage"][i]), "use": int(d["use"][i]), "units": int(d["units"][i]),
		"owner": int(d["owner_id"][i]), "reason": int(d["reason_id"][i]), "code": int(d["last_code"][i])}


func _qa_stage(run: Dictionary, id: int) -> int:
	return int(_qa_econ(run, id)["stage"])


func _qa_zone(run: Dictionary, id: int) -> String:
	return String(_land_f(run).parcel_views(PackedInt64Array([id]))[0].zone)


## Komutu gönderir, 1 tick ilerletir ve UYGULAMADA reddedilmediğini doğrular.
func _qa_do(run: Dictionary, command: SimCommand) -> CommandResult:
	var result := _land_do(run, command)
	for entry: Dictionary in Commands.rejected(_land_f(run).game_state()):
		assert_int(int(entry["seq"]) + 1).override_failure_message("uygulamada reddedildi: %s" % str(entry)) \
			.is_not_equal(result.command_id)
	return result


## Komutu gönderir (ilerletmez), reddedilmesini ve hiçbir şeyin değişmediğini doğrular. Ret `why` argümanını döner.
func _qa_assert_rejected(run: Dictionary, command: SimCommand, label: String) -> String:
	var before := _qa_snap(run)
	var validated := _land_f(run).validate_command(command)
	assert_bool(validated.is_rejected()).override_failure_message("%s: validate kabul etti" % label).is_true()
	var result := _land_f(run).submit_command(command)
	assert_bool(result.is_rejected()).override_failure_message("%s: submit kabul etti" % label).is_true()
	_qa_assert_same(run, before, label)
	return String(result.args.get("why", ""))


## Önerinin yürürlüğe girmesini bekler (ilk parsel VACANT olana dek; üst sınır 80 gün).
func _qa_reopen(run: Dictionary, ids: PackedInt64Array, use: StringName = &"zone.green") -> CommandResult:
	var result := _qa_do(run, _land_command(ids, use))
	for _day in 80:
		if _qa_stage(run, int(ids[0])) == EconomyState.STAGE_VACANT:
			break
		_land_f(run).advance(1)
	return result


func _qa_demolished(mode: String = "direct", isolate: bool = false) -> Dictionary:
	var run := _land_setup(mode, LAND_P.SEED, isolate)
	var built := _land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	run["road_command_id"] = built.command_id
	_land_do(run, SimCommand.public_work_demolish(built.command_id))
	_land_assert_taken(run)
	return run


func _qa_free_parcel(run: Dictionary, excluded: Array) -> int:
	var ids: Array = _qa_net(run).parcels.keys()
	ids.sort()
	for id: int in ids:
		if not excluded.has(id):
			return id
	return -1


func _qa_event_count(run: Dictionary, command_id: int, key: StringName) -> int:
	return _land_events_for(run, command_id, key).size()


func _qa_overlay(run: Dictionary, id: int) -> Dictionary:
	return ParcelZoningSystem.overlay_of(_land_f(run).game_state(), id)


## Her gün kaydedip KALICI hedefe yükler: yükleme başarılı ve sim/ağ özeti kaynakla bit-eşit olmalı.
func _qa_sweep(run: Dictionary, target: Dictionary, days: int, label: String) -> int:
	var checked := 0
	for day in days:
		_land_f(run).advance(1)
		var result := _land_f(target).import_save(_land_f(run).export_save())
		assert_bool(result.ok).override_failure_message(
			"%s gün %d: meşru kayıt yüklenemedi: %s %s" % [label, day, result.error_code, result.message]).is_true()
		if not result.ok:
			return checked
		assert_str(_land_f(target).state_hash()).override_failure_message("%s gün %d sim" % [label, day]) \
			.is_equal(_land_f(run).state_hash())
		assert_str(_qa_net(target).state_hash()).override_failure_message("%s gün %d ağ" % [label, day]) \
			.is_equal(_qa_net(run).state_hash())
		checked += 1
	return checked


func _qa_tamper(saved: PackedByteArray, target: Dictionary, edit: Callable, label: String) -> String:
	var envelope: Dictionary = bytes_to_var(saved)
	var body: Dictionary = envelope["state"]
	edit.call(body)
	envelope["state_hash"] = StateHash.of(body)
	var before := _qa_snap(target)
	var loaded := _land_f(target).import_save(var_to_bytes(envelope))
	assert_bool(loaded.ok).override_failure_message("%s: bozuk kayıt YÜKLENDİ" % label).is_false()
	var now := _qa_snap(target)
	for key in LOAD_KEYS:
		assert_that(now[key]).override_failure_message("%s: %s değişti" % [label, key]).is_equal(before[key])
	for key in ["graph_version", "revision"]:
		assert_int(int(now[key])).override_failure_message("%s: %s geri gitti" % [label, key]) \
			.is_greater_equal(int(before[key]))
	return String(loaded.error_code)


func _qa_scripted(mode: String, seed_value: int, chunked: bool) -> Dictionary:
	var run := _land_setup(mode, seed_value)
	var f := _land_f(run)
	var built := _land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_do(run, SimCommand.public_work_demolish(built.command_id))
	_land_do(run, _land_command(run["taken"]))
	if chunked:
		for _i in 90:
			f.advance(1)
	else:
		f.advance(90)
	return {"sim": f.state_hash(), "net": _qa_net(run).state_hash(), "events": f.last_event_seq(),
		"stage": _qa_stage(run, int((run["taken"] as PackedInt64Array)[0]))}


# --- seçim biçimleri ---

func test_mixed_selection_rejects_the_whole_group_and_changes_nothing() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var net := _qa_net(run)
	var a_ids: PackedInt64Array = run["taken"]
	var b_points := PackedInt64Array(SECOND_ROAD)
	var b_ids := RoadDraftCheck.taken_parcels(net, RoadDraftCheck.points_from_cm(b_points), &"local")
	assert_int(b_ids.size()).is_greater(0)
	for id in b_ids:
		assert_bool(a_ids.has(id)).is_false()
	_land_do(run, SimCommand.public_work_road(b_points, &"local", true))
	_land_assert_taken(run, b_ids)
	var free_id := _qa_free_parcel(run, [])
	assert_int(free_id).is_greater(0)
	var with_standing := a_ids.duplicate()
	with_standing.append(b_ids[0])
	var standing_first := PackedInt64Array([b_ids[0]])
	standing_first.append_array(a_ids)
	var with_free := a_ids.duplicate()
	with_free.append(free_id)
	var with_unknown := a_ids.duplicate()
	with_unknown.append(999999)
	assert_str(_qa_assert_rejected(run, _land_command(with_standing), "karışık: duran yol")).is_equal(WHY_STANDING)
	assert_str(_qa_assert_rejected(run, _land_command(standing_first), "karışık: duran yol başta")) \
		.is_equal(WHY_STANDING)
	assert_str(_qa_assert_rejected(run, _land_command(b_ids), "yalnız duran yol")).is_equal(WHY_STANDING)
	assert_str(_qa_assert_rejected(run, _land_command(with_free), "karışık: hiç alınmamış parsel")) \
		.is_equal(WHY_NOT_AVAILABLE)
	_qa_assert_rejected(run, _land_command(with_unknown), "karışık: olmayan parsel")
	_qa_assert_rejected(run, _land_command(PackedInt64Array([free_id])), "yalnız alınmamış özel parsel")
	# Önizleme de aynı kapıdan geçer ve durumu değiştirmez.
	var before := _qa_snap(run)
	assert_bool(f.plan_preview(with_standing, &"zone.green", -1, -1, true).ok).is_false()
	assert_bool(f.plan_preview(with_free, &"zone.green", -1, -1, true).ok).is_false()
	_qa_assert_same(run, before, "önizleme")
	# Reddedilen karışık teklifler sonrası yalnız uygun grup sorunsuz açılır; duran yolun parselleri kapalı kalır.
	_qa_reopen(run, a_ids)
	_land_assert_fresh_green(run, a_ids)
	_land_assert_taken(run, b_ids)
	var rows := f.municipal_lands()
	assert_int(rows.size()).is_equal(b_ids.size())
	for row in rows:
		assert_bool(b_ids.has(row.id)).is_true()
		assert_bool(row.available).is_false()
		assert_str(String(row.reason_key)).is_equal(WHY_STANDING)


func test_duplicate_ids_and_the_parcel_cap_never_corrupt_state_and_survive_save_load() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var many := PackedInt64Array()
	for _i in 41:
		many.append(int((run["taken"] as PackedInt64Array)[0]))
	_qa_assert_rejected(run, _land_command(many), "parsel üst sınırı")
	_qa_assert_rejected(run, _land_command(PackedInt64Array()), "boş seçim")
	var ids: PackedInt64Array = (run["taken"] as PackedInt64Array).duplicate()
	var dup := ids.duplicate()
	dup.append(ids[0])
	dup.append(ids[ids.size() - 1])
	dup.append(ids[0])
	var before := _qa_snap(run)
	var result := f.submit_command(_land_command(dup))
	if result.is_rejected():
		_qa_assert_same(run, before, "yinelenen kimlik reddi")
		return
	f.advance(1)
	assert_int(Commands.rejected(f.game_state()).size()).override_failure_message("yinelenenli komut uygulamada düştü") \
		.is_equal(0)
	assert_str(ParcelZoningSystem.municipal_problem(f.game_state())).is_empty()
	var fresh := _land_setup()
	assert_bool(_land_f(fresh).import_save(f.export_save()).ok).is_true()
	f.advance(12)
	_land_assert_fresh_green(run)
	assert_int(_qa_event_count(run, result.command_id, &"event.zoning.applied")).is_equal(ids.size())
	var reloaded := _land_setup()
	assert_bool(_land_f(reloaded).import_save(f.export_save()).ok).is_true()
	assert_str(_land_f(reloaded).state_hash()).is_equal(f.state_hash())
	assert_str(_qa_net(reloaded).state_hash()).is_equal(_qa_net(run).state_hash())


# --- çift uygulama / sıralama ---

func test_same_tick_second_municipal_plan_is_rejected_and_the_group_stays_whole() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var first := f.submit_command(_land_command(ids, &"zone.green"))
	var second := f.submit_command(_land_command(PackedInt64Array([ids[0]]), &"zone.mixed"))
	var third := f.submit_command(_land_command(ids, &"zone.mixed"))
	assert_str(String(first.status)).is_equal("queued")
	assert_str(String(second.status)).is_equal("queued")
	assert_str(String(third.status)).is_equal("queued")
	f.advance(1)
	var rejected_ids: Array = []
	for entry: Dictionary in Commands.rejected(f.game_state()):
		rejected_ids.append(int(entry["seq"]) + 1)
	assert_array(rejected_ids).contains_exactly_in_any_order([second.command_id, third.command_id])
	for id in ids:
		var overlay := _qa_overlay(run, id)
		assert_int(int(overlay["command_id"])).is_equal(first.command_id)
		assert_str(String(overlay["pending_zone"])).is_equal("zone.green")
		assert_int((overlay["municipal_group"] as Array).size()).is_equal(ids.size())
	assert_str(ParcelZoningSystem.municipal_problem(f.game_state())).is_empty()
	_land_assert_taken(run)
	f.advance(12)
	_land_assert_fresh_green(run)
	assert_int(_qa_event_count(run, first.command_id, &"event.zoning.applied")).is_equal(ids.size())
	assert_int(_qa_event_count(run, second.command_id, &"event.zoning.applied")).is_equal(0)
	assert_int(_qa_event_count(run, third.command_id, &"event.zoning.applied")).is_equal(0)


func test_same_tick_ordinary_plan_first_blocks_the_municipal_one_without_marks() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var one := PackedInt64Array([ids[0]])
	var ordinary := f.submit_command(_land_command(one, &"zone.mixed", false))
	var municipal := f.submit_command(_land_command(ids))
	assert_str(String(ordinary.status)).is_equal("queued")
	assert_str(String(municipal.status)).is_equal("queued")
	f.advance(1)
	var rejected := Commands.rejected(f.game_state())
	assert_int(rejected.size()).is_equal(1)
	assert_int(int(rejected[0]["seq"]) + 1).is_equal(municipal.command_id)
	assert_bool(_qa_overlay(run, ids[0]).has("municipal_reuse")).is_false()
	assert_str(String(_qa_overlay(run, ids[0])["pending_zone"])).is_equal("zone.mixed")
	for i in range(1, ids.size()):
		assert_bool(_qa_overlay(run, ids[i]).is_empty()).is_true()
	assert_str(ParcelZoningSystem.municipal_problem(f.game_state())).is_empty()
	f.advance(12)
	_land_assert_taken(run)
	assert_str(_qa_zone(run, ids[0])).is_equal("zone.mixed")
	# Bekleyen plan yürürlüğe girince belediye arazisi teklifi artık geçerli.
	_qa_reopen(run, ids)
	_land_assert_fresh_green(run)


# --- bekleyen plan sırasında başka yol ---

func test_road_over_pending_land_makes_the_plan_fail_closed_and_a_later_plan_succeeds() -> void:
	var run := _qa_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var plan := _qa_do(run, _land_command(ids))
	var due := int(_qa_overlay(run, ids[0])["due_tick"])
	var over := f.submit_command(SimCommand.public_work_road(_land_points(), &"local", true))
	assert_str(String(over.status)).override_failure_message("yol reddi: %s" % over.reason_key).is_equal("queued")
	f.advance(1)
	assert_int(Commands.rejected(f.game_state()).size()).is_equal(0)
	var before := _qa_snap(run)
	var rows := f.municipal_lands()
	for row in rows:
		assert_bool(row.available).is_false()
	f.advance(due - f.current_tick())
	assert_int(_qa_event_count(run, plan.command_id, &"event.zoning.applied")).is_equal(0)
	var rejected_events := _land_events_for(run, plan.command_id, &"event.zoning.plan_rejected")
	assert_int(rejected_events.size()).is_equal(1)
	assert_str(String(rejected_events[0].args.get("why", ""))).is_equal(WHY_WORLD)
	for key in ["net", "graph", "graph_version", "ops", "parcels", "revision"]:
		assert_that(_qa_snap(run)[key]).override_failure_message("ret ağı değiştirdi: %s" % key).is_equal(before[key])
	_land_assert_taken(run)
	for id in ids:
		var overlay := _qa_overlay(run, id)
		assert_str(String(overlay["pending_zone"])).is_empty()
		assert_int(int(overlay["rejected_command"])).is_equal(plan.command_id)
		assert_bool(overlay.has("municipal_reuse") or overlay.has("municipal_group")).is_false()
	assert_str(ParcelZoningSystem.municipal_problem(f.game_state())).is_empty()
	assert_str(ExpropriationFlow.consistency_problem(f.game_state())).is_empty()
	var fresh := _land_setup()
	assert_bool(_land_f(fresh).import_save(f.export_save()).ok).is_true()
	assert_str(_land_f(fresh).state_hash()).is_equal(f.state_hash())
	# Üstteki yol yıkılınca aynı arazi yeniden önerilebilir.
	_qa_do(run, SimCommand.public_work_demolish(over.command_id))
	for row in f.municipal_lands():
		assert_bool(row.available).is_true()
	_qa_reopen(run, ids)
	_land_assert_fresh_green(run)


# --- meclis yolu ---

func test_council_route_every_day_save_loads_and_continues_bit_identically() -> void:
	var run := _qa_demolished("pass")
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	_qa_do(run, _land_command(ids))
	var saves: Array[Dictionary] = []
	var seen_vote := false
	var seen_overlay := false
	for _day in 70:
		var vote := CouncilEngine.pending_vote_for_parcel(f.game_state(), int(ids[0])) > 0
		var overlay := not String(_qa_overlay(run, ids[0]).get("pending_zone", "")).is_empty()
		seen_vote = seen_vote or vote
		seen_overlay = seen_overlay or overlay
		saves.append({"tick": f.current_tick(), "bytes": f.export_save(), "stage": _qa_stage(run, ids[0])})
		if _qa_stage(run, ids[0]) == EconomyState.STAGE_VACANT:
			break
		f.advance(1)
	assert_bool(seen_vote).override_failure_message("oy bekleyen kayıt yok").is_true()
	assert_bool(seen_overlay).override_failure_message("yürürlük bekleyen kayıt yok").is_true()
	_land_assert_fresh_green(run)
	f.advance(20)
	var final_tick := f.current_tick()
	var persistent := _land_setup("pass")
	for entry in saves:
		var result := _land_f(persistent).import_save(entry["bytes"])
		assert_bool(result.ok).override_failure_message("tick %d: %s" % [entry["tick"], result.message]).is_true()
		_land_f(persistent).advance(final_tick - _land_f(persistent).current_tick())
		assert_str(_land_f(persistent).state_hash()).override_failure_message("tick %d" % entry["tick"]) \
			.is_equal(f.state_hash())
		assert_str(_qa_net(persistent).state_hash()).override_failure_message("ağ tick %d" % entry["tick"]) \
			.is_equal(_qa_net(run).state_hash())
	# Taze bir dünyaya ilk (oy bekleyen) ve son (yürürlük bekleyen) kayıt.
	for entry in [saves[0], saves[saves.size() - 2]]:
		var fresh := _land_setup("pass")
		assert_bool(_land_f(fresh).import_save(entry["bytes"]).ok).is_true()
		_land_f(fresh).advance(final_tick - _land_f(fresh).current_tick())
		assert_str(_land_f(fresh).state_hash()).is_equal(f.state_hash())


func test_failed_vote_state_is_clean_across_save_load_and_can_be_resubmitted() -> void:
	var run := _qa_demolished("fail")
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var plan := _qa_do(run, _land_command(ids))
	for _day in 60:
		if _qa_event_count(run, plan.command_id, &"event.zoning.plan_rejected") > 0:
			break
		f.advance(1)
	assert_int(_qa_event_count(run, plan.command_id, &"event.zoning.plan_rejected")).is_greater(0)
	_land_assert_taken(run)
	assert_str(ParcelZoningSystem.municipal_problem(f.game_state())).is_empty()
	var target := _land_setup("fail")
	var loaded := _land_f(target).import_save(f.export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_land_f(target).state_hash()).is_equal(f.state_hash())
	for row in _land_f(target).municipal_lands():
		assert_bool(row.available).is_true()
	var again := _land_f(target).submit_command(_land_command(ids))
	assert_str(String(again.status)).is_equal("queued")
	_land_f(target).advance(1)
	assert_int(CouncilEngine.pending_vote_for_parcel(_land_f(target).game_state(), int(ids[0]))).is_greater(0)


# --- yanlış-pozitif taraması ---

func test_legitimate_states_in_direct_mode_never_load_as_corrupt() -> void:
	var run := _qa_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var others := _qa_free_parcel(run, [])
	var target := _land_setup()
	assert_int(_qa_sweep(run, target, 2, "plan öncesi")).is_equal(2)
	# Aynı tick'te belediye planı + başka parsellerde sıradan plan.
	f.submit_command(_land_command(PackedInt64Array([others]), &"zone.mixed", false))
	f.submit_command(_land_command(ids))
	assert_int(_qa_sweep(run, target, 22, "doğrudan")).is_equal(22)
	_land_assert_fresh_green(run)


func test_legitimate_states_in_council_mode_never_load_as_corrupt() -> void:
	var run := _qa_demolished("pass")
	var target := _land_setup("pass")
	_land_f(run).submit_command(_land_command(run["taken"]))
	assert_int(_qa_sweep(run, target, 45, "meclis")).is_equal(45)
	_land_assert_fresh_green(run)


func test_legitimate_rejection_path_states_never_load_as_corrupt() -> void:
	var run := _qa_demolished()
	var f := _land_f(run)
	var target := _land_setup()
	_qa_do(run, _land_command(run["taken"]))
	f.submit_command(SimCommand.public_work_road(_land_points(), &"local", true))
	assert_int(_qa_sweep(run, target, 8, "yol üstte")).is_equal(8)
	_land_assert_taken(run)


# --- GERİ AL / yıkım / ikinci döngü ---

func test_undo_last_after_reopening_is_closed_and_changes_nothing() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var net := _qa_net(run)
	var b_points := PackedInt64Array(SECOND_ROAD)
	_qa_do(run, SimCommand.public_work_road(b_points, &"local", true))
	_qa_reopen(run, run["taken"])
	_land_assert_fresh_green(run)
	assert_bool(f.undo_available()).override_failure_message("açılıştan sonra geri al penceresi açık").is_false()
	_qa_assert_rejected(run, SimCommand.public_work_undo_last(), "açılıştan sonra GERİ AL")
	assert_int(f.public_works().size()).is_equal(1)
	assert_int(net.delta.ops.size()).is_equal(PublicWorksState.work_count(f.game_state()))


func test_reexpropriate_then_undo_restores_empty_green_land_not_old_buildings() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	_qa_reopen(run, ids)
	_land_assert_fresh_green(run)
	var rows_before: Array = []
	for id in ids:
		rows_before.append(_qa_econ(run, id))
	var net_before := _qa_net(run).state_hash()
	var data_before: Dictionary = PublicWorksState.data(f.game_state())
	var displaced_before := StateHash.of(data_before["displaced"])
	var latent_before := _land_latent(run)
	var road := _qa_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_assert_taken(run)
	_qa_do(run, SimCommand.public_work_undo_last())
	assert_str(_qa_net(run).state_hash()).override_failure_message("ağ geri alma sonrası farklı").is_equal(net_before)
	_land_assert_fresh_green(run)
	for i in ids.size():
		var now := _qa_econ(run, ids[i])
		for key in ["stage", "use", "units", "owner"]:
			assert_int(int(now[key])).override_failure_message("parsel %d %s" % [ids[i], key]) \
				.is_equal(int(rows_before[i][key]))
	assert_int(PublicWorksState.taken_count(f.game_state())).is_equal(0)
	assert_str(StateHash.of(PublicWorksState.data(f.game_state())["displaced"])).is_equal(displaced_before)
	assert_array(Array(_land_latent(run))).is_equal(Array(latent_before))
	assert_bool(f.municipal_lands().is_empty()).is_true()
	assert_str(_qa_assert_rejected(run, _land_command(ids), "geri alınmış arazi yeniden açılamaz")) \
		.is_equal(WHY_NOT_AVAILABLE)
	assert_int(road.command_id).is_greater(0)
	var fresh := _land_setup()
	var loaded := _land_f(fresh).import_save(f.export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_land_f(fresh).state_hash()).is_equal(f.state_hash())
	assert_str(_qa_net(fresh).state_hash()).is_equal(_qa_net(run).state_hash())


func test_second_cycle_and_arbitrary_rewinds_between_saved_states_are_bit_equal() -> void:
	var run := _land_setup()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var marks: Array[Dictionary] = []
	var built := _qa_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	marks.append(_qa_mark(run, "yol1"))
	_qa_do(run, SimCommand.public_work_demolish(built.command_id))
	marks.append(_qa_mark(run, "yıkık1"))
	_qa_reopen(run, ids)
	_land_assert_fresh_green(run)
	marks.append(_qa_mark(run, "açık1"))
	var second := _qa_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_assert_taken(run)
	marks.append(_qa_mark(run, "yol2"))
	_qa_do(run, SimCommand.public_work_demolish(second.command_id))
	_land_assert_taken(run)
	marks.append(_qa_mark(run, "yıkık2"))
	for row in f.municipal_lands():
		assert_bool(row.available).is_true()
		assert_int(row.source_command_id).is_equal(second.command_id)
	_qa_reopen(run, ids, &"zone.mixed")
	assert_str(_qa_zone(run, ids[0])).is_equal("zone.mixed")
	assert_int(_qa_stage(run, ids[0])).is_equal(EconomyState.STAGE_VACANT)
	marks.append(_qa_mark(run, "açık2"))
	assert_str(ExpropriationFlow.consistency_problem(f.game_state())).is_empty()
	assert_array(NetworkInvariants.check_parcels(_qa_net(run))).is_empty()
	assert_array(NetworkInvariants.check_graph_integrity(_qa_net(run))).is_empty()
	var order := [5, 0, 3, 1, 4, 2, 5, 3, 0, 4, 5, 2, 1, 5]
	var target := _land_setup()
	for index: int in order:
		var mark := marks[index]
		var result := _land_f(target).import_save(mark["bytes"])
		assert_bool(result.ok).override_failure_message("%s: %s %s" % [mark["label"], result.error_code,
			result.message]).is_true()
		if not result.ok:
			return
		assert_str(_land_f(target).state_hash()).override_failure_message("%s sim" % mark["label"]) \
			.is_equal(mark["sim"])
		assert_str(_qa_net(target).state_hash()).override_failure_message("%s ağ" % mark["label"]) \
			.is_equal(mark["net"])
		assert_int(PublicWorksState.taken_count(_land_f(target).game_state())).is_equal(mark["taken"])
		assert_str(ExpropriationFlow.consistency_problem(_land_f(target).game_state())).is_empty()
		assert_array(NetworkInvariants.check_parcels(_qa_net(target))).is_empty()


func _qa_mark(run: Dictionary, label: String) -> Dictionary:
	var f := _land_f(run)
	return {"label": label, "bytes": f.export_save(), "sim": f.state_hash(), "net": _qa_net(run).state_hash(),
		"taken": PublicWorksState.taken_count(f.game_state())}


# --- ağ/parsel tutarlılığı, salt okunur sorgular ---

func test_lifecycle_rows_are_honest_read_only_and_the_world_stays_consistent() -> void:
	var run := _land_setup()
	var f := _land_f(run)
	var net := _qa_net(run)
	var ids: PackedInt64Array = run["taken"]
	var all_before: Array = net.parcels.keys()
	all_before.sort()
	assert_bool(f.municipal_lands().is_empty()).is_true()
	var built := _qa_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	assert_int(f.municipal_lands().size()).is_equal(ids.size())
	for row in f.municipal_lands():
		assert_bool(row.available).is_false()
		assert_str(String(row.reason_key)).is_equal(WHY_STANDING)
	_qa_do(run, SimCommand.public_work_demolish(built.command_id))
	var before := _qa_snap(run)
	for row in f.municipal_lands():
		assert_bool(row.available).is_true()
		assert_int(row.area_m2).is_greater(0)
		assert_bool(String(row.region_code).is_empty()).is_false()
	assert_bool(f.validate_command(_land_command(ids)).is_rejected()).is_false()
	_qa_assert_same(run, before, "salt okunur sorgular")
	_qa_do(run, _land_command(ids))
	for row in f.municipal_lands():
		assert_str(String(row.reason_key)).is_equal(WHY_PENDING)
		assert_bool(row.available).is_false()
	f.advance(12)
	_land_assert_fresh_green(run)
	assert_bool(f.municipal_lands().is_empty()).is_true()
	assert_int(net.parcel_revision).is_equal(before["revision"] + 1)
	assert_int(net.graph_version).is_equal(before["graph_version"])
	assert_str(net.graph_hash()).is_equal(before["graph"])
	assert_int(net.delta.ops.size()).is_equal(before["ops"] + 1)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	var all_after: Array = net.parcels.keys()
	all_after.sort()
	assert_array(all_after).override_failure_message("parsel kimlik kümesi değişti (yeni kimlik/kayıp)") \
		.is_equal(all_before)
	for id in ids:
		assert_int((net.parcels[id] as WorldParcel).owner_id).is_equal(0)
	var block_membership := {}
	for block_id: int in net.blocks:
		for parcel_id: int in (net.blocks[block_id] as WorldBlock).parcel_ids:
			assert_bool(block_membership.has(parcel_id)).override_failure_message("parsel iki blokta: %d" % parcel_id) \
				.is_false()
			block_membership[parcel_id] = block_id
	assert_int(block_membership.size()).is_equal(net.parcels.size())


func test_plan_preview_of_available_municipal_land_is_ok_and_read_only() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var before := _qa_snap(run)
	var preview := f.plan_preview(run["taken"], &"zone.green", -1, -1, true)
	assert_object(preview).is_not_null()
	assert_bool(preview.ok).override_failure_message("uygun arazi önizlemesi ok değil: %s" % str(preview.reason)) \
		.is_true()
	_qa_assert_same(run, before, "uygun arazi önizlemesi")


# --- ekonomi / CAN-03 ---

func test_reopening_alone_builds_nothing_even_after_half_a_year() -> void:
	var run := _qa_demolished("direct", true)
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	var d := EconomyState.data(f.game_state())
	var before := {}
	for column in ["stage", "use", "units", "owner_id"]:
		before[column] = d[column].duplicate()
	_qa_reopen(run, ids)
	_land_assert_fresh_green(run)
	d = EconomyState.data(f.game_state())
	var group := {}
	for id in ids:
		group[EconomyState.index_of(d, id)] = true
	for i in (d["stage"] as PackedByteArray).size():
		if group.has(i):
			continue
		for column in ["stage", "use", "units", "owner_id"]:
			assert_int(int(d[column][i])).override_failure_message("grup dışı parsel %d %s değişti" % [i, column]) \
				.is_equal(int(before[column][i]))
	f.advance(180)
	for id in ids:
		var row := _qa_econ(run, id)
		assert_int(int(row["stage"])).is_equal(EconomyState.STAGE_VACANT)
		assert_int(int(row["units"])).is_equal(0)
		assert_int(int(row["owner"])).is_equal(0)


func test_buildings_appear_on_reopened_land_only_through_recorded_investor_decisions() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var ids: PackedInt64Array = run["taken"]
	_qa_reopen(run, ids, &"zone.residential")
	var first_tick := f.current_tick()
	for id in ids:
		var row := _qa_econ(run, id)
		assert_int(int(row["units"])).override_failure_message("açılış anında bina var").is_equal(0)
		assert_int(int(row["owner"])).is_equal(0)
	var built := 0
	for _day in 400:
		f.advance(1)
		for id in ids:
			var row := _qa_econ(run, id)
			if int(row["stage"]) == EconomyState.STAGE_VACANT:
				assert_int(int(row["units"])).is_equal(0)
				continue
			assert_int(int(row["owner"])).override_failure_message("sahipsiz yapı: parsel %d" % id).is_greater(0)
			assert_int(int(row["reason"])).override_failure_message("gerekçesiz yatırım: parsel %d" % id) \
				.is_greater(0)
			var reasons := f.reasons_for(SimContract.parcel_ref(id))
			var has_develop := false
			for reason in reasons:
				if reason.decision_key == EconomyState.DEVELOP_DECISION and reason.tick > first_tick:
					has_develop = true
			assert_bool(has_develop).override_failure_message("yatırım kararı kaydı yok: parsel %d" % id).is_true()
			if int(row["units"]) > 0:
				built += 1
	assert_int(built).override_failure_message("400 günde hiçbir yatırımcı açılan arazide karar vermedi (gözlem)") \
		.is_greater(0)


# --- determinizm ---

func test_identical_runs_have_identical_hashes_and_the_seed_matters() -> void:
	for mode in ["direct", "pass"]:
		var first := _qa_scripted(mode, LAND_P.SEED, false)
		var second := _qa_scripted(mode, LAND_P.SEED, false)
		var chunked := _qa_scripted(mode, LAND_P.SEED, true)
		assert_dict(second).override_failure_message("%s: aynı koşu farklı" % mode).is_equal(first)
		assert_dict(chunked).override_failure_message("%s: parçalı ilerleme farklı" % mode).is_equal(first)
		assert_int(int(first["stage"])).is_equal(EconomyState.STAGE_VACANT)
		var other := _qa_scripted(mode, LAND_P.SEED + 7, false)
		assert_str(String(other["sim"])).override_failure_message("%s: tohum etkisiz" % mode) \
			.is_not_equal(String(first["sim"]))


# --- bozma biçimleri ---

func test_more_tamper_shapes_of_a_pending_group_are_corrupt_and_non_mutating() -> void:
	var source := _land_demolished()
	_land_do(source, _land_command(source["taken"]))
	var ids: PackedInt64Array = source["taken"]
	assert_int(ids.size()).is_greater(1)
	var saved := _land_f(source).export_save()
	var target := _land_setup("direct", LAND_P.SEED + 1)
	_land_do(target, LAND_P.road(LAND_P.spur_b_cm()))
	var first := int(ids[0])
	var second := int(ids[1])
	var edits := {
		"grup ters sıra": func(body: Dictionary) -> void:
			(body["systems"]["parcels"]["overlay"][first]["municipal_group"] as Array).reverse(),
		"üye farklı imar": func(body: Dictionary) -> void:
			body["systems"]["parcels"]["overlay"][second]["pending_zone"] = &"zone.mixed",
		"üye farklı vade": func(body: Dictionary) -> void:
			body["systems"]["parcels"]["overlay"][second]["due_tick"] += 1,
		"grup dizge kimlik": func(body: Dictionary) -> void:
			var strings: Array = []
			for id in ids:
				strings.append(str(id))
			body["systems"]["parcels"]["overlay"][first]["municipal_group"] = strings,
		"grup sözlük": func(body: Dictionary) -> void:
			body["systems"]["parcels"]["overlay"][first]["municipal_group"] = {"x": 1},
		"grup yinelenen": func(body: Dictionary) -> void:
			(body["systems"]["parcels"]["overlay"][first]["municipal_group"] as Array).append(first),
		"bekleyen yok işaret var": func(body: Dictionary) -> void:
			body["systems"]["parcels"]["overlay"][first]["pending_zone"] = &"",
		"yalnız ilk üyede işaret yok": func(body: Dictionary) -> void:
			body["systems"]["parcels"]["overlay"][first].erase("municipal_reuse"),
	}
	var codes := {}
	for label: String in edits:
		codes[label] = _qa_tamper(saved, target, edits[label], label)
		assert_str(codes[label]).override_failure_message("%s: hata kodu" % label).is_equal("corrupt")


func test_tampered_applied_reopening_ledger_is_rejected_and_non_mutating() -> void:
	var source := _land_demolished()
	var ids: PackedInt64Array = source["taken"]
	_qa_reopen(source, ids)
	_land_assert_fresh_green(source)
	var saved := _land_f(source).export_save()
	var target := _land_setup("direct", LAND_P.SEED + 1)
	_land_do(target, LAND_P.road(LAND_P.spur_b_cm()))
	var free_id := _qa_free_parcel(source, Array(ids))
	var edits := {
		"fazladan parsel": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["works"][-1]["parcel_ids"].append(free_id),
		"işlem parselleri sırasız": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["ops"][-1]["parcel_ids"].reverse(),
		"yanlış kaynak işlem": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["ops"][-1]["source_op"] = 5,
		"sürüm 2": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["version"] = 2,
		"yanlış kaynak komut": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["works"][-1]["source_command_id"] += 1,
		"graf özeti": func(body: Dictionary) -> void:
			body["systems"]["public_works"]["hashes"][-1] = "00",
		"defterden düşürülmüş açılış": func(body: Dictionary) -> void:
			var section: Dictionary = body["systems"]["public_works"]
			(section["ops"] as Array).pop_back()
			(section["hashes"] as Array).pop_back()
			(section["works"] as Array).pop_back(),
		"ekonomi TAKEN'e döndürülmüş": func(body: Dictionary) -> void:
			var economy: Dictionary = body["systems"]["economy"]
			var index: int = (economy["parcel_ids"] as PackedInt64Array).find(ids[0])
			economy["stage"][index] = EconomyState.STAGE_TAKEN,
	}
	for label: String in edits:
		var code := _qa_tamper(saved, target, edits[label], label)
		assert_bool(["corrupt", "network_mismatch"].has(code)).override_failure_message("%s: kod %s" % [label, code]) \
			.is_true()
