extends PoliticsTestBase
## T-043A köprüsü · `SimFacade.plan_state` / `plan_preview` (sözleşme 1.4): gerçek facade üzerinden UI'ın okuyacağı
## salt okunur sorgular. Sayılar `EconomySystem` sorgularıyla BİREBİR (yatırımcının kullandığı formül; ayrı hesap yok).
## Meclis yolunda bekleyen oylama facade içinde çözülür (UI siyaset bilmez); `council_required` gerçek siyaset
## yapılandırmasından (`requires_council.zoning.propose`) gelir.

const ENABLED := {"decision": {"unplanned_land_enabled": 1}}
const MIXED := &"zone.mixed"


func _no_council(f: Dictionary) -> void:
	f["council"]["requires_council"]["zoning.propose"] = false


func _propose(h: PoliticsHandle, ids: PackedInt64Array, land_use: StringName = MIXED) -> CommandResult:
	return h.facade.submit_command(SimCommand.zoning_propose(ids, land_use))


func test_plan_state_walks_unplanned_proposed_planned_and_matches_the_economy_query() -> void:
	var h := handle(ENABLED, 6, SEED, _no_council)
	var id := int(h.facade.parcel_ids()[0])
	h.facade.advance(1)
	var st := h.facade.plan_state(id)
	assert_str(String(st.state)).is_equal("unplanned")
	assert_int(st.parcel_id).is_equal(id)
	assert_str(String(st.provenance)).is_equal("sim")
	var result := _propose(h, PackedInt64Array([id]))
	h.facade.advance(1)
	st = h.facade.plan_state(id)
	var raw := h.economy.plan_state(h.state(), id)
	assert_str(String(st.state)).is_equal("proposed")
	assert_str(String(st.pending_zone)).is_equal(String(raw["pending_zone"]))
	assert_int(st.due_tick).is_equal(int(raw["due_tick"]))
	assert_str(String(st.source_ref)).is_equal("command.%d" % result.command_id)
	assert_int(st.command_id).is_equal(result.command_id)
	h.facade.advance(5)
	st = h.facade.plan_state(id)
	assert_str(String(st.state)).is_equal("planned")
	assert_str(String(st.zone)).is_equal(String(MIXED))
	assert_str(String(st.source_ref)).is_equal("command.%d" % result.command_id)


func test_plan_state_resolves_the_pending_council_vote_internally() -> void:
	var h := handle(ENABLED, 6)  # varsayılan siyaset: meclis var
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(2)
	var vote_id := CouncilEngine.pending_vote_for_parcel(h.state(), id)
	assert_int(vote_id).is_greater(0)
	var st := h.facade.plan_state(id)
	assert_str(String(st.state)).is_equal("proposed")
	assert_str(String(st.vote_ref)).is_equal("vote.%d" % vote_id)
	assert_int(st.due_tick).override_failure_message("yürürlük oylamadan sonra: bilinmiyor").is_equal(-1)


func test_plan_state_is_untracked_without_the_flag_and_for_unknown_parcels() -> void:
	var off := handle({}, 6, SEED, _no_council)
	off.facade.advance(1)
	assert_str(String(off.facade.plan_state(int(off.facade.parcel_ids()[0])).state)).is_equal("untracked")
	var on := handle(ENABLED, 6, SEED, _no_council)
	on.facade.advance(1)
	assert_str(String(on.facade.plan_state(999999).state)).override_failure_message("bilinmeyen parsel plan sayılmaz") \
		.is_equal("untracked")


func test_plan_preview_equals_the_economy_preview_number_for_number() -> void:
	var h := handle(ENABLED, 6, SEED, _no_council)
	h.facade.advance(1)
	var ids := h.facade.parcel_ids(&"F1").slice(0, 4)
	var raw := h.economy.plan_preview(h.state(), ids, &"zone.residential", 500, 12)
	var pv := h.facade.plan_preview(ids, &"zone.residential", 500, 12)
	assert_bool(pv.ok).is_true()
	assert_bool(raw["ok"]).is_true()
	assert_int(pv.total_units).is_equal(int(raw["total_units"]))
	assert_int(pv.total_infra_units).is_equal(int(raw["total_infra_units"]))
	assert_int(pv.parcels.size()).is_equal((raw["parcels"] as Array).size())
	for i in pv.parcels.size():
		var a: Dictionary = pv.parcels[i]
		var b: Dictionary = raw["parcels"][i]
		assert_int(int(a["id"])).is_equal(int(b["id"]))
		assert_int(int(a["units"])).is_equal(int(b["units"]))
		assert_int(int(a["infra_units"])).is_equal(int(b["infra_units"]))
		assert_str(String(a["use"])).is_equal(String(b["use"]))
		assert_str(String(a["region"])).is_equal(String(b["region"]))
	assert_int(pv.regions.size()).is_equal((raw["regions"] as Array).size())
	for i in pv.regions.size():
		for key: String in ["added_units", "added_infra_units", "capacity_units", "load_units", "headroom_units"]:
			assert_int(int(pv.regions[i][key])).is_equal(int(raw["regions"][i][key]))
		assert_bool(bool(pv.regions[i]["fits"])).is_equal(bool(raw["regions"][i]["fits"]))
	assert_int(pv.total_units).override_failure_message("önizleme boş olmamalı").is_greater(0)


func test_plan_preview_reports_the_real_council_flag_and_the_proposal_limit() -> void:
	var with_council := handle(ENABLED, 6)
	with_council.facade.advance(1)
	var p1 := with_council.facade.plan_preview(with_council.facade.parcel_ids().slice(0, 1), MIXED)
	assert_bool(p1.council_required).is_true()
	assert_int(p1.max_parcels).is_equal(FacadeConfig.load_default().plan_max_parcels_per_proposal)
	var direct := handle(ENABLED, 6, SEED, _no_council)
	direct.facade.advance(1)
	var p2 := direct.facade.plan_preview(direct.facade.parcel_ids().slice(0, 1), MIXED)
	assert_bool(p2.council_required).override_failure_message("meclis yok ise UI 'meclis' demez").is_false()


func test_plan_preview_failure_reasons_come_from_the_sim() -> void:
	var h := handle(ENABLED, 6, SEED, _no_council)
	assert_str(String(h.facade.plan_preview(PackedInt64Array([1]), MIXED).reason)).is_equal("economy.not_started")
	h.facade.advance(1)
	assert_str(String(h.facade.plan_preview(PackedInt64Array([1]), &"zone.nope").reason)).is_equal("plan.unknown_land_use")
	var bad := h.facade.plan_preview(PackedInt64Array([999999]), MIXED)
	assert_bool(bad.ok).is_false()
	assert_str(String(bad.reason)).is_equal("plan.unknown_parcel")


func test_plan_queries_are_read_only() -> void:
	var h := handle(ENABLED, 6)
	h.facade.advance(3)
	_propose(h, h.facade.parcel_ids().slice(0, 3))
	h.facade.advance(2)
	var before := h.facade.state_hash()
	var observed := StateHash.of(SimContractChecks.observable_state(h.facade))
	for id in h.facade.parcel_ids():
		h.facade.plan_state(int(id))
	h.facade.plan_preview(h.facade.parcel_ids(), MIXED)
	assert_str(h.facade.state_hash()).is_equal(before)
	assert_str(StateHash.of(SimContractChecks.observable_state(h.facade))).is_equal(observed)


func test_contract_checks_stay_clean_with_the_plan_flag_on() -> void:
	var h := handle(ENABLED, 6, SEED, _no_council)
	h.facade.advance(2)
	_propose(h, h.facade.parcel_ids().slice(0, 3))
	h.facade.advance(10)
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()
