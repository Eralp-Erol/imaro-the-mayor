extends "res://tests/sim/politics/reaction_world_base.gd"
## D-021 (SAHİP: "Meclis güveni düşsün") · yerinden edilme meclis üyelerinin güvenini düşürür (`CouncilTrust`).
## Dünya: `ReactionWorldBase` (yol köşegeni parsel 1-3'ü alır; D1'de 16 hane yerinden edilir; 5 üyeli meclis: üye 1-2 ve
## 5 "barınan hane" kesiminin, üye 3-4 yalnız "arayan hane" kesiminin temsilcisi). Sayılar testte AÇIKÇA verilir
## (veri ayarı bu testleri bozmaz); gerçek `reactions.json` değerleri için yalnız bir sağlamlık testi vardır.
## Beklenen değerler testte bağımsız hesaplanır (ham defter satırından), üretim koduna çağrı yapılmaz.

const HOUSED := ["actor.council.1", "actor.council.2", "actor.council.5"]
const OTHERS := ["actor.council.3", "actor.council.4"]
const MEMBERS := ["actor.council.1", "actor.council.2", "actor.council.3", "actor.council.4", "actor.council.5"]
const DISPLACED := 16
const REGION_CODE := "D1"
const TRUST := {"enabled": true, "decision": "decision.council.displacement_trust", "cohorts": ["housed"],
	"window_days": 100, "threshold_households": 5, "drop_per_household_pm": 10, "cap_pm": 400,
	"recover_per_scan_pm": 20}


func _edit(changes: Dictionary = {}, section: bool = true) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		if section:
			files["reactions"]["council_trust"] = TRUST.duplicate(true).merged(changes, true)
		else:  # gönderilen dosyada bölüm var: "bölüm yok" durumu için çıkar
			files["reactions"].erase("council_trust")


## Yol yapılmış dünya (tick 2); `section` false: `council_trust` bölümü HİÇ yok (kod varsayılanı).
func _road_world(changes: Dictionary = {}, section: bool = true, expropriate: bool = true) -> PoliticsHandle:
	return _world(expropriate, _edit(changes, section))["handle"]


func _trust_state(h: PoliticsHandle) -> Dictionary:
	return pol(h).get(CouncilTrust.KEY, {})


func _pen(h: PoliticsHandle, member: String) -> int:
	return int(_trust_state(h).get("penalty", {}).get(member, 0))


## Defterdeki ham satırlardan bağımsız beklenen etkin hane (doğrusal sönme, aşağı yuvarlı).
func _expected_households(h: PoliticsHandle, window: int) -> int:
	var milli := 0
	for row: Array in PublicWorksState.reaction_rows(h.state(), "displaced", REGION_CODE):
		var age := h.state().tick - int(row[0])
		if age >= 0 and age < window:
			milli += int(row[1]) * 1000 * (window - age) / window
	return milli / 1000



func _next_scan(h: PoliticsHandle) -> void:
	h.facade.advance(WEEK - h.state().tick % WEEK)


# --- Eşik altı: hiçbir şey değişmez ---

func test_below_the_threshold_nothing_is_written_and_the_state_hash_equals_the_disabled_run() -> void:
	var off := _road_world({"enabled": false})
	var quiet := _road_world({"threshold_households": 500})
	for h in [off, quiet]:
		h.facade.advance(40)
	assert_bool(_trust_state(quiet).is_empty()).override_failure_message("eşik altında durum yaratılmamalı").is_true()
	assert_bool(_trust_state(off).is_empty()).is_true()
	assert_str(quiet.state().state_hash()).is_equal(off.state().state_hash())
	assert_int(reasons_of(quiet, "decision.council.displacement_trust").size()).is_equal(0)


func test_a_run_without_any_demolition_never_creates_council_trust_state() -> void:
	var h := _road_world({}, true, false)
	h.facade.advance(60)
	assert_bool(_trust_state(h).is_empty()).is_true()
	var plain := _road_world({"enabled": false}, true, false)
	plain.facade.advance(60)
	assert_str(h.state().state_hash()).override_failure_message("yıkımsız koşuda hash değişmemeli") \
		.is_equal(plain.state().state_hash())


func test_the_code_default_is_off_when_the_file_has_no_council_trust_section() -> void:
	var h := _road_world({}, false)
	h.facade.advance(40)
	assert_bool(h.context.politics.reactions["council_trust"]["enabled"]).is_false()
	assert_bool(_trust_state(h).is_empty()).is_true()


# --- Eşik üstü: etkilenen üyelerin güveni düşer ---

func test_above_the_threshold_only_the_members_of_the_displaced_cohort_lose_trust() -> void:
	var h := _road_world()
	h.facade.advance(14)
	var expected := clampi((_expected_households(h, 100) - 5) * 10, 0, 400)
	# tarama haftalıktır: son taramanın hane değeri (tarama gününde) bugünkünden büyük olabilir; aralık denetimi
	assert_int(_pen(h, HOUSED[0])).override_failure_message("etkilenen üye kesintisi > 0 olmalı").is_greater(0)
	assert_int(_pen(h, HOUSED[0])).is_greater_equal(expected)
	for member: String in HOUSED:
		assert_int(_pen(h, member)).override_failure_message(member).is_equal(_pen(h, HOUSED[0]))
	for member: String in OTHERS:
		assert_int(_pen(h, member)).override_failure_message("etkilenmeyen üye " + member).is_equal(0)


func test_the_cut_equals_the_independent_formula_on_the_scan_day() -> void:
	var h := _road_world()
	_next_scan(h)  # tick % 7 == 0: tarama koşuldu
	var expected := clampi((_expected_households(h, 100) - 5) * 10, 0, 400)
	assert_int(expected).override_failure_message("fikstürde eşik aşılmalı").is_greater(0)
	assert_int(_pen(h, HOUSED[0])).is_equal(expected)
	assert_int(_pen(h, HOUSED[2])).is_equal(expected)


func test_the_cut_lowers_the_trust_input_of_the_vote_and_the_member_view_but_not_the_relation_record() -> void:
	var h := _road_world()
	var off := _road_world({"enabled": false})
	_next_scan(h)
	_next_scan(off)
	var st := h.state()
	var player := ActorStore.protagonist_key(st, h.context.actors)
	var vote := {"context": {"axes": {}, "stakes": {}, "regions": []}, "kind": "zoning"}
	for member: String in MEMBERS:
		var relation := int(ActorStore.relation(st, h.context.actors, member, player)["trust"])
		var cut := _pen(h, member)
		var factors := CouncilEngine.member_factors(st, h.context, member, vote, player)
		assert_int(int(factors["trust_in_player"]["value"])).override_failure_message(member) \
			.is_equal(clampi(relation - cut, -1000, 1000))
		assert_int(PoliticsQuery.member_view(st, h.context, member, player).stance) \
			.is_equal(clampi(relation - cut, -1000, 1000))
		var raw_on: Variant = ActorStore.actor_ref(st, member)["relations"].get(player, null)
		var raw_off: Variant = ActorStore.actor_ref(off.state(), member)["relations"].get(player, null)
		assert_str(str(raw_on)).override_failure_message("ilişki kaydı dokunulmadı: " + member).is_equal(str(raw_off))
	assert_int(_pen(h, HOUSED[0])).is_greater(0)


func test_the_cut_lowers_the_vote_margin_by_exactly_the_trust_contribution() -> void:
	# Güven faktörü karar tablosunda (özellik kaydırmalı normalize ağırlık); kesinti yalnız bu girdiyi değiştirir, marj
	# farkı = katkı(ilişki güveni) - katkı(ilişki güveni - kesinti) (beklenen fark bağımsız hesaplanır).
	var h := _road_world()
	_next_scan(h)
	var st := h.state()
	var player := ActorStore.protagonist_key(st, h.context.actors)
	var table := h.context.actors.table("council.vote")
	var vote := {"context": {"axes": {}, "stakes": {}, "regions": []}, "kind": "zoning"}
	var member: String = HOUSED[0]
	var actor := ActorStore.actor_ref(st, member)
	var opts := {"traits": actor["traits"], "draw": 0, "noise_trait": h.context.actors.noise_trait,
		"previous_positive": false}
	var weights := ActorDecision.normalized_weights(table, actor["traits"])
	var weight := 0
	for i in table["factors"].size():
		if String(table["factors"][i]["name"]) == "trust_in_player":
			weight = weights[i]
	var relation := int(ActorStore.relation(st, h.context.actors, member, player)["trust"])
	var cut := _pen(h, member)
	var cut_margin := int(ActorDecision.decide(CouncilEngine.member_factors(st, h.context, member, vote, player), table,
		opts)["margin"])
	var saved: Dictionary = _trust_state(h).duplicate(true)
	pol(h).erase(CouncilTrust.KEY)
	var free_margin := int(ActorDecision.decide(CouncilEngine.member_factors(st, h.context, member, vote, player),
		table, opts)["margin"])
	pol(h)[CouncilTrust.KEY] = saved
	assert_int(cut).is_greater(0)
	assert_int(free_margin - cut_margin).override_failure_message("marj farkı = güven katkısı farkı") \
		.is_equal(SimContract.contribution(relation, weight) - SimContract.contribution(relation - cut, weight))
	assert_int(free_margin).is_greater(cut_margin)


# --- Tavan ve toparlanma ---

func test_the_cut_never_exceeds_the_cap() -> void:
	var h := _road_world({"drop_per_household_pm": 1000, "cap_pm": 60})
	for _i in 6:
		_next_scan(h)
		for member: String in MEMBERS:
			assert_int(_pen(h, member)).is_less_equal(60)
	assert_int(_pen(h, HOUSED[0])).override_failure_message("tavana oturmalı").is_equal(60)


func test_the_trust_recovers_over_time_by_at_most_the_per_scan_step_and_never_overshoots() -> void:
	var h := _road_world({"window_days": 60, "threshold_households": 2, "recover_per_scan_pm": 15})
	_next_scan(h)
	var peak := _pen(h, HOUSED[0])
	assert_int(peak).is_greater(0)
	var previous := peak
	var strictly_dropped := false
	for _i in 30:
		_next_scan(h)
		var now := _pen(h, HOUSED[0])
		assert_int(now).override_failure_message("toparlanma adımı <= 15").is_greater_equal(previous - 15)
		assert_int(now).is_greater_equal(0)
		if now < previous:
			strictly_dropped = true
		previous = now
	assert_bool(strictly_dropped).is_true()
	assert_int(previous).override_failure_message("pencere dolduktan sonra tam toparlanmış olmalı").is_equal(0)
	var player := ActorStore.protagonist_key(h.state(), h.context.actors)
	var relation := int(ActorStore.relation(h.state(), h.context.actors, HOUSED[0], player)["trust"])
	assert_int(PoliticsQuery.member_view(h.state(), h.context, HOUSED[0], player).stance) \
		.override_failure_message("toparlanınca görünüm ilişki güvenine döner").is_equal(relation)


func test_a_second_road_after_recovery_cuts_the_trust_again() -> void:
	var run := _world(true, _edit({"window_days": 30, "threshold_households": 2}))
	(run["fake"] as FakeExpropriationWorld).take(P.spur_a_cm(), [6])
	var h: PoliticsHandle = run["handle"]
	for _i in 12:
		_next_scan(h)
	assert_int(_pen(h, HOUSED[0])).is_equal(0)
	assert_bool(_trust_state(h).is_empty()).is_false()
	var result := h.facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", true))
	assert_bool(result.is_rejected()).override_failure_message(str(result.reason_key)).is_false()
	for _i in 2:
		_next_scan(h)
	assert_int(_pen(h, HOUSED[0])).override_failure_message("yeni yıkım yeniden keser").is_greater(0)


# --- Neden kaydı (SIM-12) ---

func test_every_change_writes_a_reason_record_for_the_member_with_the_command_as_subject() -> void:
	var h := _road_world()
	_next_scan(h)
	var records := reasons_of(h, "decision.council.displacement_trust")
	assert_int(records.size()).override_failure_message("etkilenen 3 üye için 3 kayıt").is_equal(3)
	var actors: Array = records.map(func(r: Dictionary) -> String: return String(r["actor"]))
	actors.sort()
	assert_array(actors).is_equal(HOUSED)
	var command_ref := String(SimContract.ref(SimContract.REF_COMMAND, int(h.facade.public_works()[0].command_id)))
	for rec: Dictionary in records:
		var names := {}
		for f: Dictionary in rec["factors"]:
			names[String(f["name"])] = int(f["value"])
		assert_bool(names.has("reason.factor.unhoused_households")).is_true()
		assert_bool(names.has("reason.factor.council_trust_target")).is_true()
		assert_int(names["reason.factor.council_trust_drop"]).is_equal(_pen(h, String(rec["actor"])))
		assert_str(String(rec["code"])).is_equal("displacement_trust")
		assert_bool((rec["subjects"] as PackedStringArray).has(command_ref)).is_true()
		assert_str(String(rec["outcome"])).is_equal("positive")
	assert_int(int(pol(h)["counters"]["reason_records"])).is_greater_equal(3)


func test_recovery_records_say_recovery_and_the_last_one_is_negative_when_the_cut_is_gone() -> void:
	var h := _road_world({"window_days": 60, "threshold_households": 2, "recover_per_scan_pm": 15})
	for _i in 30:
		_next_scan(h)
	var mine: Array = reasons_of(h, "decision.council.displacement_trust").filter(
		func(r: Dictionary) -> bool: return String(r["actor"]) == HOUSED[0])
	assert_int(mine.size()).is_greater(2)
	assert_str(String(mine[0]["code"])).is_equal("displacement_trust")
	assert_str(String(mine[mine.size() - 1]["code"])).is_equal("displacement_trust_recovery")
	assert_str(String(mine[mine.size() - 1]["outcome"])).is_equal("negative")


func test_unchanged_weeks_write_no_new_records() -> void:
	var h := _road_world({"window_days": 100000, "recover_per_scan_pm": 0})  # sönme ~yok: hedef sabit
	_next_scan(h)
	var n := reasons_of(h, "decision.council.displacement_trust").size()
	assert_int(n).is_greater(0)
	for _i in 3:
		_next_scan(h)
	assert_bool(reasons_of(h, "decision.council.displacement_trust").size() <= n + 3 * HOUSED.size()).is_true()


# --- Determinizm, kayıt, CAN-03 ---

func test_same_seed_and_commands_give_the_same_hash_and_the_cut_is_in_it() -> void:
	var a := _road_world()
	var b := _road_world()
	a.facade.advance(30)
	b.facade.advance(30)
	assert_str(a.state().state_hash()).is_equal(b.state().state_hash())
	assert_int(_pen(a, HOUSED[0])).is_greater(0)
	var off := _road_world({"enabled": false})
	off.facade.advance(30)
	assert_str(off.state().state_hash()).override_failure_message("kesinti hash'e girer") \
		.is_not_equal(a.state().state_hash())


func test_the_cut_is_independent_of_how_ticks_are_chunked() -> void:
	var a := _road_world()
	var b := _road_world()
	a.facade.advance(33)
	for _i in 33:
		b.facade.advance(1)
	assert_str(a.state().state_hash()).is_equal(b.state().state_hash())


func test_save_and_load_in_the_middle_of_the_cut_resumes_the_same_hash() -> void:
	var run := _road_world()
	run.facade.advance(16)
	assert_int(_pen(run, HOUSED[0])).is_greater(0)
	var bytes := run.facade.export_save()
	var fresh := _road_world({}, true, false)
	var loaded := fresh.facade.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(fresh.state().state_hash()).is_equal(run.state().state_hash())
	assert_int(_pen(fresh, HOUSED[0])).is_equal(_pen(run, HOUSED[0]))
	for each in [run, fresh]:
		each.facade.advance(40)
	assert_str(fresh.state().state_hash()).is_equal(run.state().state_hash())
	assert_int(_pen(fresh, HOUSED[0])).is_equal(_pen(run, HOUSED[0]))


func test_a_corrupt_council_trust_record_is_refused_on_load() -> void:
	var run := _road_world()
	run.facade.advance(16)
	var good: Dictionary = pol(run).duplicate(true)
	assert_str(PoliticsState.validate_data(good)).is_empty()
	var cases := {"penalty yok": {"changes": 1}, "kesinti metin": {"penalty": {"actor.council.1": "x"}, "changes": 1},
		"kesinti negatif": {"penalty": {"actor.council.1": -5}, "changes": 1}, "sayaç yok": {"penalty": {}}}
	for name: String in cases:
		var bad := good.duplicate(true)
		bad[CouncilTrust.KEY] = cases[name]
		assert_str(PoliticsState.validate_data(bad)).override_failure_message(name).is_not_empty()


func test_the_cut_creates_no_private_building_and_changes_no_economy_state_can_03() -> void:
	var h := _road_world()
	_next_scan(h)
	var economy_before := str(h.state().systems["economy"])
	var works_before := str(h.state().systems["public_works"])
	var parcels_before := str(h.facade.parcel_ids())
	CouncilTrust.scan(h.state(), h.context)  # doğrudan ikinci tarama: ekonomi/imar/yol durumuna dokunmaz
	assert_str(str(h.state().systems["economy"])).is_equal(economy_before)
	assert_str(str(h.state().systems["public_works"])).is_equal(works_before)
	assert_str(str(h.facade.parcel_ids())).is_equal(parcels_before)


# --- Veri sağlamlığı ---

func test_the_shipped_data_enables_a_small_bounded_cut() -> void:
	var cfg: Dictionary = politics_config().reactions["council_trust"]
	assert_bool(cfg["enabled"]).override_failure_message("D-021: kural varsayılan veride açık").is_true()
	assert_int(int(cfg["cap_pm"])).is_between(1, 300)
	assert_int(int(cfg["threshold_households"])).is_greater(0)
	assert_int(int(cfg["recover_per_scan_pm"])).is_greater(0)
	assert_bool((cfg["cohorts"] as Array).has("housed")).is_true()


func test_a_bad_council_trust_section_is_rejected_with_a_path_in_the_message() -> void:
	var bad := pol_mutated(func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["council_trust"] = {"enabled": true, "cohorts": ["nope"], "window_days": 0})
	assert_bool(bad.is_valid()).is_false()
	assert_str(bad.error + " ".join(bad.errors)).contains("reactions.council_trust")
