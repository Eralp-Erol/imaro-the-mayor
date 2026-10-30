extends PoliticsTestBase
## T-043A (sim yarısı) · Plan teklifi + `requires_council` (Q-014 AÇIK): iki yol da veriyle çalışır.
## true: oylama geçmezse `plan_rejected` (parsel plansız kalır, yeniden teklif mümkün); geçerse gecikme + sürtünmeyle
## yürürlük. false: `apply_delay_days` sonra doğrudan yürürlük. Bayrak (`unplanned_land_enabled`) kapalıyken ret kaydı
## YAZILMAZ (eski davranış bit-eşit). Meclis yalnız koşulu değiştirir (CAN-03).

const AXIS := "growth_vs_preservation"
const MEMBERS: Array[String] = [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]
const RIGGED_AXES := {"zoning": {"zone.mixed": {"growth_vs_preservation": -1000}}}
const ENABLED := {"decision": {"unplanned_land_enabled": 1}}


func _rig(f: Dictionary) -> void:
	f["council"]["proposal_axes"] = RIGGED_AXES
	f["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {}}}


func _no_council(f: Dictionary) -> void:
	_rig(f)
	f["council"]["requires_council"]["zoning.propose"] = false


func _stance(h: PoliticsHandle, yes: bool) -> void:
	for member in MEMBERS:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"][AXIS] = -1000 if yes else 1000


func _propose(h: PoliticsHandle, parcels: PackedInt64Array) -> CommandResult:
	return h.facade.submit_command(SimCommand.zoning_propose(parcels, &"zone.mixed"))


func _plan(h: PoliticsHandle, parcel_id: int) -> Dictionary:
	return h.economy.plan_state(h.state(), parcel_id)


func _events(h: PoliticsHandle, message_key: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in h.facade.events_since(0):
		if e.message_key == message_key:
			out.append(e)
	return out


func test_failed_council_vote_leaves_the_parcels_unplanned_with_a_plan_rejected_record() -> void:
	var h := handle(ENABLED, 6, SEED, _rig)
	_stance(h, false)
	var ids := PackedInt64Array([h.facade.parcel_ids()[0], h.facade.parcel_ids()[1]])
	var result := _propose(h, ids)
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(40)
	for id in ids:
		var st := _plan(h, id)
		assert_str(String(st["state"])).is_equal("plan_rejected")
		assert_int(st["rejected_command_id"]).is_equal(result.command_id)
		assert_str(String(st["source_ref"])).is_equal("command.%d" % result.command_id)
		assert_str(String(st["zone"])).is_equal("")
		assert_str(String(h.facade.parcel_views(PackedInt64Array([id]))[0].zone)).is_equal("")
	var rejected := _events(h, &"event.zoning.plan_rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0].command_id).is_equal(result.command_id)
	assert_int(rejected[0].subjects.size()).is_equal(2)
	assert_int(EconomyQuery.totals(h.state()).get("approvals", 0)).override_failure_message("ret bina yaratmaz") \
		.is_equal(0)


func test_open_vote_shows_the_parcel_as_proposed_with_the_vote_reference() -> void:
	var h := handle(ENABLED, 6, SEED, _rig)
	_stance(h, true)
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(2)
	var vote_id := CouncilEngine.pending_vote_for_parcel(h.state(), id)
	assert_int(vote_id).is_greater(0)
	var st := h.economy.plan_state(h.state(), id, vote_id)
	assert_str(String(st["state"])).is_equal("proposed")
	assert_int(st["due_tick"]).override_failure_message("yürürlük oylamadan sonra").is_equal(-1)
	assert_str(String(st["vote_ref"])).is_equal("vote.%d" % vote_id)
	assert_str(String(_plan(h, id)["state"])).override_failure_message("oylama bilinmezse plansız").is_equal("unplanned")


func test_after_a_rejection_the_same_parcels_can_be_proposed_again_and_pass() -> void:
	var h := handle(ENABLED, 6, SEED, _rig)
	_stance(h, false)
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(30)
	assert_str(String(_plan(h, id)["state"])).is_equal("plan_rejected")
	_stance(h, true)
	var again := _propose(h, PackedInt64Array([id]))
	assert_bool(again.is_rejected()).override_failure_message("yeniden teklif mümkün olmalı").is_false()
	h.facade.advance(30)
	var st := _plan(h, id)
	assert_str(String(st["state"])).is_equal("planned")
	assert_str(String(st["zone"])).is_equal("zone.mixed")
	assert_int(int(st.get("rejected_command_id", 0))).override_failure_message("eski ret izi temizlenmeli").is_equal(0)


func test_passing_council_vote_applies_the_plan_after_session_and_friction() -> void:
	var h := handle(ENABLED, 6, SEED, _rig)
	_stance(h, true)
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(14)  # oylama çözüldü: yürürlük 14 + 3 + 3
	assert_str(String(_plan(h, id)["state"])).is_equal("proposed")
	h.facade.advance(8)
	assert_str(String(_plan(h, id)["state"])).is_equal("planned")
	assert_int(_events(h, &"event.zoning.plan_rejected").size()).is_equal(0)


func test_without_council_the_plan_takes_effect_after_the_apply_delay_with_no_vote() -> void:
	var h := handle(ENABLED, 6, SEED, _no_council)
	assert_bool(h.context.politics.requires_council("zoning.propose")).is_false()
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(1)
	assert_str(String(_plan(h, id)["state"])).is_equal("proposed")
	h.facade.advance(4)
	assert_str(String(_plan(h, id)["state"])).is_equal("planned")
	assert_int(pol_votes(h)).is_equal(0)


func pol_votes(h: PoliticsHandle) -> int:
	return (PoliticsState.data(h.state())["council"]["votes"] as Array).size()


func test_with_the_flag_off_a_failed_vote_writes_no_rejection_record_and_no_event() -> void:
	var h := handle({}, 6, SEED, _rig)
	_stance(h, false)
	var id := int(h.facade.parcel_ids()[0])
	_propose(h, PackedInt64Array([id]))
	h.facade.advance(40)
	assert_str(String(h.facade.snapshot().council.votes[0].status)).is_equal("failed")
	assert_int(_events(h, &"event.zoning.plan_rejected").size()).is_equal(0)
	assert_bool(ParcelZoningSystem.overlay_ref(h.state()).has(id)) \
		.override_failure_message("bayrak kapalıyken bindirme yazılmaz").is_false()
	assert_str(String(_plan(h, id)["state"])).is_equal("untracked")


func test_council_path_is_deterministic_and_survives_save_load() -> void:
	var a := handle(ENABLED, 6, SEED, _rig)
	var b := handle(ENABLED, 6, SEED, _rig)
	var c := handle(ENABLED, 6, SEED, _rig)
	for h in [a, b, c]:
		_stance(h, false)
		_propose(h, PackedInt64Array([h.facade.parcel_ids()[0]]))
	a.facade.advance(60)
	b.facade.advance(60)
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())
	c.facade.advance(20)
	var bytes := c.facade.export_save()
	var d := handle(ENABLED, 6, SEED, _rig)
	var loaded := d.facade.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	d.facade.advance(40)
	assert_str(d.facade.state_hash()).is_equal(a.facade.state_hash())
