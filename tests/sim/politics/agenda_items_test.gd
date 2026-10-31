extends "res://tests/sim/politics/reaction_world_base.gd"
## T-042b gündem sözleşmesi, GERÇEK sim (ADR-0005 Ek F): `SimFacadeImpl.agenda_items()` olay motorunun AÇIK öğelerini
## (PE-01 yerinden edilme dahil) `AgendaItemView` olarak verir. Okuma salt okunur (hash değişmez); kamulaştırmasız
## koşuda ve siyasetsiz facade'de PE-01 yok; gerekçe zinciri `cause_refs`e komut + parselleri taşır (SIM-12).

const CAUSE_KEY := "decision.bloc.expropriation_cause"


func _items(h: PoliticsHandle) -> Array[AgendaItemView]:
	return h.facade.agenda_items()


func _command_ref(h: PoliticsHandle) -> String:
	return "command.%d" % h.facade.public_works()[0].command_id


func test_a_facade_without_politics_reports_an_empty_agenda() -> void:
	var f := SimFacadeImpl.create(SEED, ListParcelSource.create(&"agenda.plain", _views()))
	assert_object(f).is_not_null()
	f.advance(10)
	assert_int(f.agenda_items().size()).is_equal(0)


func test_runs_without_expropriation_have_no_displacement_item() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	h.facade.advance(30)
	for it in _items(h):
		assert_str(String(it.template_id)).is_not_equal("PE-01")


func test_displacement_opens_a_pe01_item_visible_through_the_contract() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var items := _items(h)
	assert_int(items.size()).override_failure_message("PE-01 öğesi sözleşmeden okunabilmeli").is_greater(0)
	var raw: Dictionary = pol(h)["events"]["agenda"][0]
	var it := items[0]
	assert_int(it.item_id).is_equal(int(raw["id"]))
	assert_str(String(it.ref())).is_equal("agenda.%d" % int(raw["id"]))
	assert_str(String(it.template_id)).is_equal("PE-01")
	assert_str(String(it.delivery)).is_equal("agenda")
	assert_str(String(it.status)).is_equal("open")
	assert_str(String(it.region_code)).is_equal("D1")  # alınan parsellerin bölgesi
	assert_int(it.opened_tick).is_equal(int(raw["opened_tick"]))
	assert_int(it.deadline_tick).is_equal(int(raw["deadline"]))
	assert_str(String(it.title_key)).is_equal("event.pe01.reason")
	assert_str(String(it.provenance)).is_equal("sim")
	assert_object(it.group).is_not_null()
	var refs: Array[String] = []
	for g in h.facade.snapshot().group_reactions:
		refs.append(String(g.group.ref()))
	assert_array(refs).contains([String(it.group.ref())])  # tetikleyen grup, snapshot'taki gruplardan biri
	assert_array(Array(it.reason_ids)).is_equal([int(raw["reason_id"])])


func test_cause_refs_carry_the_command_and_taken_parcels_from_the_recorded_cause() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var it := _items(h)[0]
	assert_bool(it.cause_refs.has(_command_ref(h))).is_true()
	assert_bool(it.cause_refs.has("parcel.1")).is_true()
	for ref in it.cause_refs:  # yalnız komut/parsel başvurusu (aktör/gündem değil)
		assert_bool(ref.begins_with("command.") or ref.begins_with("parcel.")).is_true()
	var fire := h.facade.reason(it.reason_ids[0])
	var parent := h.facade.reason(fire.parent_ids[0])
	assert_str(String(parent.decision_key)).is_equal(CAUSE_KEY)


func test_the_contract_checks_pass_on_the_real_item_and_the_whole_facade() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	assert_int(_items(h).size()).is_greater(0)
	assert_array(Array(SimContractChecks.check_agenda(h.facade))).is_empty()
	assert_array(Array(SimContractChecks.check_facade(h.facade))).is_empty()


func test_reading_the_agenda_never_changes_the_state_hash() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var twin: PoliticsHandle = _world()["handle"]
	twin.facade.advance(14)
	for _i in 3:
		_items(h)
	assert_str(h.facade.state_hash()).is_equal(twin.facade.state_hash())  # okuma yapmayan ikiz aynı durumda
	h.facade.advance(30)
	twin.facade.advance(30)
	assert_str(h.facade.state_hash()).is_equal(twin.facade.state_hash())


func test_closed_items_leave_the_open_agenda_list() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var raw: Dictionary = pol(h)["events"]["agenda"][0]
	var item_id := int(raw["id"])
	raw["status"] = "expired"  # kapanmış öğe (yalnız okuma sorgusunu sınar)
	for it in _items(h):
		assert_int(it.item_id).is_not_equal(item_id)


func test_a_loaded_save_reports_the_same_items() -> void:
	var first: PoliticsHandle = _world()["handle"]
	first.facade.advance(20)
	var restored: PoliticsHandle = _world(false)["handle"]
	assert_bool(restored.facade.import_save(first.facade.export_save()).ok).is_true()
	var a := _items(first)
	var b := _items(restored)
	assert_int(a.size()).is_greater(0)
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_bool(b[i].same_as(a[i])).is_true()
