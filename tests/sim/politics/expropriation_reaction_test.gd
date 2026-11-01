extends "res://tests/sim/politics/reaction_world_base.gd"
## T-042b adım 2 (sim) · Halk tepkisi (D-011, SIM-05/SIM-12): kamulaştırma halkın tepkisinin girdisi olur. Esas tepki
## yerinden edilmeye (`displacement`), yola yakın ama yerinden edilmeyenler daha hafif ve mesafeye bağlı (`proximity`);
## ikisi de YALNIZ yol parsel aldıysa hesaplanır (yolsuz/düz yol koşusunda kesim durumu değişmez), zamanla söner ve yol
## GERİ ALINSA bile geri alınmaz. Dünya köprüsü test ikizidir; koordinatlar sınanan mesafeleri belirler (yakın parsel
## 25 m).

func test_without_expropriation_the_optional_signals_never_enter_the_bloc_state() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	scan_blocs(h)
	assert_bool(pol(h)["blocs"][BLOC_HOUSED]["signals"].has("displacement")).is_false()
	h.facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))  # düz yol
	h.facade.advance(1)
	scan_blocs(h)
	assert_bool(pol(h)["blocs"][BLOC_HOUSED]["signals"].has("proximity")).is_false()
	assert_bool(PublicWorksState.has_reactions(h.state())).is_false()


func test_displacement_is_the_main_reaction_and_proximity_is_lighter_and_distance_dependent() -> void:
	var h: PoliticsHandle = _world()["handle"]
	var state := h.state()
	assert_int(h.facade.public_works()[0].displaced_households).is_greater(0)
	var rows := PublicWorksState.reaction_rows(state, "nearby", "D1")
	assert_int(rows.size()).is_equal(1)
	# Parsel 6: 6 birim x barınan oranı, ağırlık = (60 - ~25) / 60 -> ham hane x ağırlık, tam ağırlıktan KÜÇÜK.
	assert_int(int(rows[0][1])).is_greater(0)
	assert_int(int(rows[0][1])).is_less(6 * 1000)  # 6 hane tam ağırlıkta 6000 olurdu: mesafe ağırlığı onu düşürür
	scan_blocs(h)
	var displacement := _signal(h, "displacement")
	var proximity := _signal(h, "proximity")
	assert_int(displacement).is_greater(0)
	assert_int(proximity).is_greater(0)
	assert_int(proximity).override_failure_message("yakınlık tepkisi yerinden edilmeden hafif olmalı") \
		.is_less(displacement)


func test_displaced_households_raise_the_housing_cost_grievance_with_a_recorded_cause() -> void:
	var control: PoliticsHandle = _world(false)["handle"]
	scan_blocs(control)
	var h: PoliticsHandle = _world()["handle"]
	scan_blocs(h)
	var after := int(bloc_book(h, BLOC_HOUSED, "grievances").get("housing_cost", 0))
	var before := int(bloc_book(control, BLOC_HOUSED, "grievances").get("housing_cost", 0))
	assert_int(after).override_failure_message("yerinden edilme şikâyeti artırmalı").is_greater(before)
	assert_int(int(bloc_book(h, BLOC_SEEKING, "grievances").get("housing_cost", 0))).is_greater_equal(
		int(bloc_book(control, BLOC_SEEKING, "grievances").get("housing_cost", 0)))
	# nedenselliğin kaynağı sim'de durur: tepki defterindeki satır ve iş kaydı aynı komuta bağlı (SIM-12)
	var rows := PublicWorksState.reaction_rows(h.state(), "displaced", "D1")
	assert_int(int(rows[0][2])).is_equal(h.facade.public_works()[0].command_id)


func test_undoing_the_road_returns_the_buildings_and_removes_the_reaction() -> void:
	var world := _world()
	var h: PoliticsHandle = world["handle"]
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(1)
	assert_str(String(h.facade.parcel_views(PackedInt64Array([1]))[0].development)).is_equal("built")
	scan_blocs(h)
	# D-014 §1 (D-011'i değiştirir): klasik geri al = hiç yapılmamış gibi; tepki siyaset taramasından önce silinir
	assert_int(_signal(h, "displacement")).override_failure_message("geri alınan yolun tepkisi kalmamalı").is_equal(0)


func test_the_reaction_fades_after_the_window() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(WINDOW + 10)
	scan_blocs(h)
	assert_int(_signal(h, "displacement")).is_equal(0)
	assert_int(_signal(h, "proximity")).is_equal(0)


func test_reaction_rows_are_pruned_by_the_keep_days_data() -> void:
	var h: PoliticsHandle = _world()["handle"]
	var state := h.state()
	var keep := PublicWorksConfig.load_default().reaction_keep_days
	state.tick += keep + 1
	PublicWorksState.note_reactions(state, 99, {}, {}, keep)
	assert_int(PublicWorksState.reaction_rows(state, "displaced", "D1").size()).is_equal(0)
	state.tick -= keep + 1


func test_same_commands_give_the_same_politics_state_hash() -> void:
	var hashes: Array[String] = []
	for _i in 2:
		var h: PoliticsHandle = _world()["handle"]
		h.facade.advance(30)
		hashes.append(h.facade.state_hash())
	assert_str(hashes[1]).is_equal(hashes[0])


func test_the_reaction_rules_live_outside_the_config_digest_so_unaffected_runs_keep_their_hash() -> void:
	var files := raw_politics()
	var without := PoliticsConfig.from_files(files, config())
	files["reactions"] = _raw_reactions()
	var with_rules := PoliticsConfig.from_files(files, config())
	assert_bool(without.is_valid() and with_rules.is_valid()).override_failure_message(with_rules.error).is_true()
	assert_str(with_rules.digest).is_equal(without.digest)
	var plain: Array = without.cohort("housed")["grievance_rules"]
	var extended: Array = with_rules.cohort("housed")["grievance_rules"]
	assert_int(extended.size()).is_equal(plain.size() + 2)
	assert_str(String(extended[extended.size() - 1]["signal"])).is_equal("proximity")  # SONA eklenir, sıra kaymaz
	assert_int(int(with_rules.blocs["reaction_window"])).is_equal(WINDOW)


func test_invalid_reaction_data_is_rejected_with_a_path() -> void:
	var files := raw_politics()
	var raw := _raw_reactions()
	raw["cohorts"]["housed"]["grievance_rules"][0]["hi"] = 5  # hi <= lo
	files["reactions"] = raw
	var cfg := PoliticsConfig.from_files(files, config())
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("reactions.cohorts.housed.grievance_rules[0]")
	var unknown := _raw_reactions()
	unknown["cohorts"]["nobody"] = {}
	files["reactions"] = unknown
	assert_bool(PoliticsConfig.from_files(files, config()).is_valid()).is_false()


func test_invalid_cause_and_agenda_data_is_rejected_with_a_path() -> void:
	var cases := {
		"reactions.agenda.template": func(raw: Dictionary) -> void: raw["agenda"]["template"] = "PE-99",
		"reactions.agenda": func(raw: Dictionary) -> void: raw["agenda"]["unknown_key"] = 1,
		"reactions.cause.weights": func(raw: Dictionary) -> void: raw["cause"]["weights"].erase("road_proximity"),
		"reactions.cause.decision": func(raw: Dictionary) -> void: raw["cause"]["decision"] = "bloc.cause",
	}
	for path: String in cases:
		var files := raw_politics()
		var raw := _raw_reactions()
		(cases[path] as Callable).call(raw)
		files["reactions"] = raw
		var cfg := PoliticsConfig.from_files(files, config())
		assert_bool(cfg.is_valid()).override_failure_message("geçerli sayıldı: %s" % path).is_false()
		assert_str(cfg.error).override_failure_message(path).contains(path)


func test_the_cause_and_agenda_defaults_apply_when_the_sections_are_absent() -> void:
	var files := raw_politics()
	var raw := _raw_reactions()
	raw.erase("cause")
	raw.erase("agenda")
	files["reactions"] = raw
	var cfg := PoliticsConfig.from_files(files, config())
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_str(String(cfg.reactions["cause"]["decision"])).is_equal("decision.bloc.expropriation_cause")
	assert_str(String(cfg.reactions["agenda"]["template"])).is_equal("PE-01")
