extends PoliticsTestBase
## Meclis oylamasının NEDENİ (SIM-12; ölçüm: production/log/2026-10-31-meclis-tepki-gercek-olcum.md §3): oylama
## çözülünce sim, üyelerin kayıtlı `council.vote` etkenlerinin oylamaya toplam etkisini `vote["why"]` olarak yazar
## (yeni etken uydurulmaz: yalnız ReasonLog'a giren etkenler). Bayrak (`unplanned_land_enabled`) kapalıyken hiçbir
## şey yazılmaz (state hash bit-eşit). Görünüm: `CouncilVoteView.why_factors` (SÜRÜM değişmez, isteğe bağlı alan).

const AXIS := "growth_vs_preservation"
const MEMBERS: Array[String] = [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]
const RIGGED_AXES := {"zoning": {"zone.mixed": {"growth_vs_preservation": -1000}}}
const ENABLED := {"decision": {"unplanned_land_enabled": 1}}
const STRINGS := "res://data/ui/strings.tr.json"


func _rig(f: Dictionary) -> void:
	f["council"]["proposal_axes"] = RIGGED_AXES
	f["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {}}}


func _stance(h: PoliticsHandle, yes: bool) -> void:
	for member in MEMBERS:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"][AXIS] = -1000 if yes else 1000


func _run(patch: Dictionary, yes: bool) -> PoliticsHandle:
	var h := handle(patch, 6, SEED, _rig)
	_stance(h, yes)
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([h.facade.parcel_ids()[0]]), &"zone.mixed"))
	h.facade.advance(40)
	return h


func _vote(h: PoliticsHandle) -> Dictionary:
	return (PoliticsState.data(h.state())["council"]["votes"] as Array)[0]


func _factor(why: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in why["factors"]:
		if f["name"] == key:
			return f
	return {}


func test_rejected_vote_records_which_factors_pushed_the_members_against() -> void:
	var h := _run(ENABLED, false)
	var vote := _vote(h)
	assert_str(String(vote["status"])).is_equal("failed")
	assert_bool(vote.has("why")).is_true()
	var why: Dictionary = vote["why"]
	assert_int(int(why["members"])).is_equal(5)
	var stance := _factor(why, "reason.factor.stance_distance")
	assert_bool(stance.is_empty()).override_failure_message("duruş uzaklığı etkeni kayıtlı olmalı").is_false()
	assert_int(int(stance["net"])).override_failure_message("düşman duruş oyları hayıra çeker").is_less(0)
	assert_int(int(stance["against"])).is_equal(5)
	assert_int(int(stance["for"])).is_equal(0)


func test_passed_vote_records_the_factors_that_carried_it() -> void:
	var h := _run(ENABLED, true)
	var vote := _vote(h)
	assert_str(String(vote["status"])).is_equal("passed")
	var stance := _factor(vote["why"], "reason.factor.stance_distance")
	assert_int(int(stance["net"])).is_greater(0)
	assert_int(int(stance["for"])).is_equal(5)


func test_net_effects_add_up_to_the_recorded_member_scores() -> void:
	# Toplam tutarlılığı: Σ etken net'i == Σ üyelerin ReasonLog skoru (aynı kayıt, ikinci bir hesap yok).
	for yes in [false, true]:
		var h := _run(ENABLED, yes)
		var vote := _vote(h)
		var from_log := 0
		for rid: int in vote["reason_ids"]:
			from_log += h.facade.reason(rid).score
		var from_why := 0
		for f: Dictionary in vote["why"]["factors"]:
			from_why += int(f["net"])
		assert_int(from_why).override_failure_message("yes=%s" % yes).is_equal(from_log)


func test_factors_are_ordered_by_influence_and_skip_inert_ones() -> void:
	var h := _run(ENABLED, false)
	var factors: Array = _vote(h)["why"]["factors"]
	assert_int(factors.size()).is_greater(1)
	for i in range(1, factors.size()):
		assert_int(absi(int(factors[i - 1]["net"]))).is_greater_equal(absi(int(factors[i]["net"])))
	for f: Dictionary in factors:
		assert_bool(int(f["net"]) != 0 or int(f["for"]) + int(f["against"]) > 0).is_true()
	assert_bool(_factor(_vote(h)["why"], "reason.factor.lobby_pressure").is_empty()) \
		.override_failure_message("sıfır etkili etken yazılmaz").is_true()


func test_zoning_vote_records_the_infrastructure_load_that_fed_budget_realism() -> void:
	var h := _run(ENABLED, false)
	var why: Dictionary = _vote(h)["why"]
	assert_bool(String(why.get("infra_region", "")).is_empty()).is_false()
	assert_int(int(why["infra_load_pm"])).is_greater_equal(0)
	var realism := _factor(why, "reason.factor.budget_realism")
	assert_bool(realism.is_empty()).is_false()


func test_flag_off_writes_no_why_and_the_view_is_empty() -> void:
	var h := _run({}, false)
	var vote := _vote(h)
	assert_str(String(vote["status"])).is_equal("failed")
	assert_bool(vote.has("why")).override_failure_message("bayrak kapalıyken yeni anahtar yazılmaz").is_false()
	assert_int(h.facade.snapshot().council.votes[0].why_factors.size()).is_equal(0)


func test_view_mirrors_the_recorded_why() -> void:
	var h := _run(ENABLED, false)
	var view: CouncilVoteView = h.facade.snapshot().council.votes[0]
	var recorded: Array = _vote(h)["why"]["factors"]
	assert_int(view.why_factors.size()).is_equal(recorded.size())
	for i in recorded.size():
		assert_str(String(view.why_factors[i].name_key)).is_equal(String(recorded[i]["name"]))
		assert_int(view.why_factors[i].net).is_equal(int(recorded[i]["net"]))
		assert_int(view.why_factors[i].against_members).is_equal(int(recorded[i]["against"]))
		assert_int(view.why_factors[i].for_members).is_equal(int(recorded[i]["for"]))
	assert_int(view.infra_load_pm).is_equal(int(_vote(h)["why"]["infra_load_pm"]))
	var back := CouncilVoteView.from_dict(view.to_dict())
	assert_bool(back.same_as(view)).is_true()
	assert_int(back.why_factors.size()).is_equal(recorded.size())


func test_why_is_deterministic_and_survives_save_load() -> void:
	var a := _run(ENABLED, false)
	var b := _run(ENABLED, false)
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())
	assert_str(StateHash.of(_vote(a)["why"])).is_equal(StateHash.of(_vote(b)["why"]))
	var loaded := handle(ENABLED, 6, SEED, _rig)
	var result := loaded.facade.import_save(a.facade.export_save())
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(StateHash.of(_vote(loaded)["why"])).is_equal(StateHash.of(_vote(a)["why"]))
	assert_str(loaded.facade.state_hash()).is_equal(a.facade.state_hash())


func test_why_does_not_create_buildings_or_change_the_vote_outcome() -> void:
	# Aynı koşu bayrak açıkken ve (ret yolu hariç) kapalıyken aynı oy sonucunu verir: nedenler yalnız kayıttır.
	var on := _run(ENABLED, false)
	var off := _run({}, false)
	assert_int(int(_vote(on)["yes"])).is_equal(int(_vote(off)["yes"]))
	assert_int(int(_vote(on)["no"])).is_equal(int(_vote(off)["no"]))
	assert_int(EconomyQuery.totals(on.state()).get("approvals", 0)).is_equal(0)


func test_every_recorded_factor_name_has_a_turkish_label_and_the_why_texts_exist() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS))
	assert_bool(parsed is Dictionary).is_true()
	var table: Dictionary = parsed
	var h := _run(ENABLED, false)
	var names := {}
	for f: Dictionary in _vote(h)["why"]["factors"]:
		names[f["name"]] = true
	# Tablodaki TÜM council.vote etkenleri (bu koşuda sıfır etkili olanlar dahil) + gürültü etiketli olmalı.
	var actors := config()
	for f: Dictionary in actors.table("council.vote")["factors"]:
		names["reason.factor.%s" % f["name"]] = true
	names["reason.factor.noise"] = true
	for key: String in names:
		assert_bool(table.has(key) and not String(table[key]).strip_edges().is_empty()) \
			.override_failure_message("metin anahtarı yok: " + key).is_true()
	for key in ["council.why.title", "council.why.against", "council.why.for", "council.why.infra",
			"council.why.members"]:
		assert_bool(table.has(key)).override_failure_message("metin anahtarı yok: " + key).is_true()
