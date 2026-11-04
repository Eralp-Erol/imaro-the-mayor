extends PoliticsTestBase
## T-017 ölçüt 5 · `SimFacadeImpl` snapshot: `groups` ve `council` bölümleri GERÇEK siyasi veriden dolar
## (`x.sim.available.* = true`), bütçe hâlâ kurulmamış; siyaset kurulmadıkça (varsayılan create) bölümler önceki gibi
## kapalıdır. `GameState.validate_dict` aktör ve siyaset bölümlerini denetler (bozuk kayıt yüklenmez).


func test_default_facade_without_politics_keeps_the_sections_unavailable() -> void:
	var f := FacadeTestSupport.facade()
	var snapshot := f.snapshot()
	for section in ["groups", "council", "budget"]:
		assert_bool(snapshot.extensions["x.sim.available.%s" % section]).is_false()
	assert_array(snapshot.group_reactions).is_empty()
	assert_array(snapshot.council.votes).is_empty()


func test_politics_facade_fills_groups_and_council_from_real_data() -> void:
	var h := stress_handle(14)
	tick(h, 150)
	var snapshot := h.facade.snapshot()
	assert_bool(snapshot.extensions["x.sim.available.groups"]).is_true()
	assert_bool(snapshot.extensions["x.sim.available.council"]).is_true()
	assert_bool(snapshot.extensions["x.sim.available.agenda"]).is_true()
	assert_bool(snapshot.extensions["x.sim.available.budget"]) \
		.override_failure_message("bütçe T-014: kurulmadı").is_false()
	assert_bool(snapshot.extensions["x.sim.available.parcels"]).is_true()
	assert_int(snapshot.group_reactions.size()).is_equal(2)
	var refs := snapshot.group_reactions.map(func(g: GroupReactionView) -> String: return String(g.group.ref()))
	assert_array(refs).is_equal([BLOC_HOUSED, BLOC_SEEKING])
	for group in snapshot.group_reactions:
		assert_bool(group.group.is_valid()).is_true()
		assert_str(String(group.group.name_key)).is_equal(String(group.group.ref()) + ".name")
		assert_array([&"neutral", &"support", &"oppose", &"protest"]).contains([group.reaction])
		assert_bool(group.stance >= -1000 and group.stance <= 1000).is_true()
		assert_bool(group.intensity >= 0 and group.intensity <= 1000).is_true()
		assert_array([&"F1", &"F2", &""]).contains([group.region_code])
		for reason_id in group.reason_ids:
			assert_bool(h.facade.reason(reason_id).is_consistent()).is_true()
	assert_int(snapshot.council.seats_total).is_equal(5)
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()
	assert_array(SimContractChecks.check_no_aggregate_score(snapshot.to_dict(), "snapshot")).is_empty()


func test_snapshot_round_trips_through_the_dto_dict_forms() -> void:
	var h := stress_handle(14)
	tick(h, 120)
	var snapshot := h.facade.snapshot()
	var again := SimSnapshot.from_dict(snapshot.to_dict())
	assert_bool(snapshot.same_as(again)).is_true()
	assert_int(again.group_reactions.size()).is_equal(snapshot.group_reactions.size())


func test_reading_the_snapshot_never_changes_the_simulation_state() -> void:
	var h := stress_handle(14)
	tick(h, 100)
	var before := h.state().state_hash()
	for i in 3:
		h.facade.snapshot()
		PoliticsQuery.agenda(h.state(), h.context, false)
		PoliticsQuery.forecasts(h.state(), h.context)
	assert_str(h.state().state_hash()).is_equal(before)


func test_snapshot_is_available_from_tick_zero() -> void:
	var h := handle()
	var snapshot := h.facade.snapshot()
	assert_bool(snapshot.extensions["x.sim.available.groups"]).is_true()
	assert_int(snapshot.group_reactions.size()).is_equal(2)
	assert_str(String(snapshot.group_reactions[0].reaction)).is_equal("neutral")


func test_state_validation_accepts_a_good_state_and_rejects_corrupt_actor_or_politics_sections() -> void:
	var h := stress_handle(14)
	tick(h, 100)
	var good := h.state().to_dict()
	assert_str(GameState.validate_dict(good)).is_empty()
	var cases: Array = [
		[func(d: Dictionary) -> void: d["systems"]["actors"]["actors"] = [], "durum.systems.actors"],
		[func(d: Dictionary) -> void: d["systems"]["actors"]["actors"][COUNCIL_1]["traits"] = 5, "traits"],
		[func(d: Dictionary) -> void: d["systems"]["actors"]["schema"] = 99, "şeması geçersiz"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["blocs"] = [], "durum.systems.politics.blocs"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["blocs"][BLOC_HOUSED]["G"] = "yüksek", "G tamsayı değil"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["council"]["votes"] = [5], "oylaması sözlük değil"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["events"]["agenda"] = {}, "events.agenda dizi değil"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["media"]["tone"] = 3, "media geçersiz"],
		[func(d: Dictionary) -> void: d["systems"]["politics"]["schema"] = 0, "politics şeması"],
	]
	for entry: Array in cases:
		var broken := good.duplicate(true)
		entry[0].call(broken)
		var problem := GameState.validate_dict(broken)
		assert_str(problem).override_failure_message("bozuk kayıt kabul edildi: %s" % entry[1]).is_not_empty()
		assert_str(problem).contains(entry[1])
		assert_object(GameState.from_dict(broken)).override_failure_message("bozuk durum yüklendi").is_null()


func test_a_corrupt_politics_section_makes_the_save_unloadable_with_a_clear_message() -> void:
	var h := stress_handle(14)
	tick(h, 60)
	var body := h.state().to_dict()
	body["systems"]["politics"]["blocs"][BLOC_HOUSED]["eval"]["reason_ids"] = "x"
	var envelope := {"format": SimSave.FORMAT, "version": SimSave.VERSION, "state_hash": StateHash.of(body), "state": body}
	var result := SimSave.decode(var_to_bytes(envelope))
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("corrupt")
	assert_str(result.message).contains("politika kesimi").contains(BLOC_HOUSED)
