extends "res://tests/sim/politics/reaction_world_base.gd"
## T-042b tepki nedenselliği (D-011, SIM-12): kamulaştırma/yakınlık tepkisi gerçek simde de gerekçe kaydıyla görünür.
## (1) Tepki gerekçesinin zincirinde `displaced_households` ve `road_proximity` etkenleri vardır (kayıt: komut,
## parseller, hane sayısı); (2) yerinden edilme PE-01 tipi gündem maddesi açar ve nedeni bu kayıttır; medya haberinin
## ebeveyni de odur (PE-04 yolu); (3) hepsi YALNIZ defter varken yazılır, kayıt/yükleme ve determinizm bozulmaz.

const CAUSE := "decision.bloc.expropriation_cause"
const F_DISPLACED := "reason.factor.displaced_households"
const F_PROXIMITY := "reason.factor.road_proximity"


func _causes(h: PoliticsHandle, actor: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec in reasons_of(h, CAUSE):
		if actor.is_empty() or String(rec["actor"]) == actor:
			out.append(rec)
	return out


func _factor(rec: Dictionary, name: String) -> Dictionary:
	for f: Dictionary in rec["factors"]:
		if String(f["name"]) == name:
			return f
	return {}


func _command_ref(h: PoliticsHandle) -> String:
	return "command.%d" % h.facade.public_works()[0].command_id


func _agenda(h: PoliticsHandle) -> Array:
	return pol(h)["events"]["agenda"]


# --- (1) Gerekçe zinciri ---

func test_runs_without_expropriation_never_write_a_cause_record() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	h.facade.advance(90)
	assert_int(_causes(h).size()).is_equal(0)
	for rec in h.state().reasons.find({}):
		assert_bool(_factor(rec, F_DISPLACED).is_empty()).is_true()


func test_the_reaction_chain_records_displaced_households_and_road_proximity_with_the_command_and_parcels() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(30)
	var causes := _causes(h, BLOC_HOUSED)
	assert_int(causes.size()).override_failure_message("kesim tepkisi nedeni kaydı yazılmalı").is_greater(0)
	var rec := causes[0]
	var displaced := _factor(rec, F_DISPLACED)
	var proximity := _factor(rec, F_PROXIMITY)
	assert_bool(displaced.is_empty() or proximity.is_empty()).is_false()
	assert_int(int(displaced["value"])).is_greater(0)
	assert_int(int(proximity["value"])).is_greater(0)
	assert_int(int(proximity["value"])).override_failure_message("yakınlık yerinden edilmeden hafif").is_less(
		int(displaced["value"]))
	assert_bool(bool(proximity["is_estimate"])).is_true()  # mesafe ağırlıklı tahmin
	assert_int(int(displaced["weight"])).is_greater(int(proximity["weight"]))  # esas tepki yerinden edilme
	assert_str(String(displaced["source_ref"])).is_equal(_command_ref(h))
	assert_bool((rec["subjects"] as PackedStringArray).has(_command_ref(h))).is_true()
	for parcel in ["parcel.1", "parcel.2", "parcel.3"]:
		assert_bool((rec["subjects"] as PackedStringArray).has(parcel)).override_failure_message(parcel).is_true()
	# hane sayısı: gösterim etkeni (ağırlık 0), komutun yerinden ettiği hane sayısıyla aynı
	var count := _factor(rec, "reason.factor.displaced_household_count")
	assert_int(int(count["weight"])).is_equal(0)
	assert_int(int(count["value"])).is_equal(h.facade.public_works()[0].displaced_households)


func test_the_groups_reaction_points_at_the_cause_and_the_react_decision_has_it_as_a_parent() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(30)
	var view := view_of(h, BLOC_HOUSED)
	assert_object(view).is_not_null()
	assert_int(view.reason_ids.size()).is_greater(0)
	var first := h.facade.reason(view.reason_ids[0])
	assert_str(String(first.decision_key)).is_equal(CAUSE)
	assert_bool(view.cause_refs.has(_command_ref(h))).is_true()
	assert_bool(view.cause_refs.has("parcel.1")).is_true()
	var cause_id := view.reason_ids[0]
	var react := h.facade.reason(view.reason_ids[1])
	assert_bool(String(react.decision_key).begins_with("decision.bloc.react")).is_true()
	assert_bool(Array(react.parent_ids).has(cause_id)).override_failure_message("tepki kararı nedene bağlı").is_true()


func test_undoing_the_road_does_not_erase_the_cause_of_the_reaction() -> void:
	var h: PoliticsHandle = _world()["handle"]
	var ref := _command_ref(h)
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(30)
	var causes := _causes(h, BLOC_HOUSED)
	assert_int(causes.size()).is_greater(0)
	assert_bool((causes[causes.size() - 1]["subjects"] as PackedStringArray).has(ref)).is_true()
	assert_int(int(_factor(causes[causes.size() - 1], F_DISPLACED)["value"])).is_greater(0)


# --- (2) Gündem ve medya ---

func test_displacement_opens_a_pe01_agenda_item_whose_cause_is_the_recorded_displacement() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	assert_int(_agenda(h).size()).override_failure_message("yerinden edilme gündem maddesi açmalı").is_greater(0)
	var item: Dictionary = _agenda(h)[0]
	assert_str(String(item["template"])).is_equal("PE-01")
	assert_str(String(item["delivery"])).is_equal("agenda")
	assert_int(int(item["opened_tick"])).is_less_equal(14)
	assert_str(String(item["region"])).is_equal("D1")  # alınan parsellerin bölgesi
	var fire := h.facade.reason(int(item["reason_id"]))
	var parents := Array(fire.parent_ids)
	var cause_ids: Array = _causes(h).map(func(r: Dictionary) -> int: return int(r["id"]))
	var linked := false
	for id: Variant in parents:
		linked = linked or cause_ids.has(int(id))
	assert_bool(linked).override_failure_message("gündem nedeni = yerinden edilme kaydı").is_true()


func test_a_displacement_agenda_item_is_not_opened_without_expropriation_or_below_its_threshold() -> void:
	var control: PoliticsHandle = _world(false)["handle"]
	control.facade.advance(14)
	assert_int(_agenda(control).size()).is_equal(0)
	var strict := func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["agenda"]["min_displacement_pm"] = 1000
	var h: PoliticsHandle = _world(true, strict)["handle"]
	h.facade.advance(14)
	assert_int(_agenda(h).size()).override_failure_message("eşik altında gündem maddesi yok").is_equal(0)


func test_the_displacement_story_reaches_the_media_with_the_cause_as_parent_for_pe04() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(21)
	var cause_ids: Array = _causes(h).map(func(r: Dictionary) -> int: return int(r["id"]))
	var covered := false
	for rec in reasons_of(h, "decision.media.coverage"):
		for id: Variant in rec["parent_ids"]:
			covered = covered or cause_ids.has(int(id))
	assert_bool(covered).override_failure_message("medya değerlendirmesi yerinden edilme nedenine bağlı").is_true()


# --- (3) Determinizm, kayıt, CAN-03 ---

func test_same_commands_give_the_same_hash_with_cause_records_and_agenda() -> void:
	var hashes: Array[String] = []
	for _i in 2:
		var h: PoliticsHandle = _world()["handle"]
		h.facade.advance(60)
		assert_int(_causes(h).size()).is_greater(0)
		hashes.append(h.facade.state_hash())
	assert_str(hashes[1]).is_equal(hashes[0])


func test_save_load_continue_equals_an_uninterrupted_run_with_the_displacement_cause() -> void:
	var straight: PoliticsHandle = _world()["handle"]
	straight.facade.advance(90)
	var first: PoliticsHandle = _world()["handle"]
	first.facade.advance(30)
	assert_int(_agenda(first).size()).is_greater(0)
	var restored: PoliticsHandle = _world(false)["handle"]
	var loaded := restored.facade.import_save(first.facade.export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(restored.facade.state_hash()).is_equal(first.facade.state_hash())
	restored.facade.advance(60)
	assert_str(restored.facade.state_hash()).is_equal(straight.facade.state_hash())


func test_the_agenda_path_never_creates_a_private_building() -> void:
	var h: PoliticsHandle = _world()["handle"]
	var before := _developed_by_sim(h)
	h.facade.advance(120)
	assert_int(_agenda(h).size()).is_greater(0)
	for item: Dictionary in _agenda(h):  # gündem seçenekleri (dinleme, telafi, geri alma, ertele) bina yerleştirmez
		if item["status"] == "open":
			Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": item["id"], "option_id": "listen"})
	h.facade.advance(30)
	for id in [1, 2, 3]:  # alınan parseller yatırımcıya dönmez
		assert_str(String(h.facade.parcel_views(PackedInt64Array([id]))[0].development)).is_equal("taken")
	assert_int(_developed_by_sim(h)).override_failure_message("CAN-03").is_greater_equal(before)
	for rec in h.state().reasons.find({"decision": "decision.investor.develop"}):
		assert_bool(["parcel.1", "parcel.2", "parcel.3"].any(func(p: String) -> bool:
			return (rec["subjects"] as PackedStringArray).has(p))).is_false()


func _developed_by_sim(h: PoliticsHandle) -> int:
	var n := 0
	for v in h.facade.parcel_views(h.facade.parcel_ids()):
		n += 1 if v.developed_by_sim else 0
	return n
