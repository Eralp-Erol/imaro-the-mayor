extends PoliticsTestBase
## D-011 Soru 4 ("İkisi de, seçenek": küçük planlar doğrudan, BÜYÜK planlar meclise) · Plan başına büyüklük kararı:
## `council.plan_council_min_parcels` / `plan_council_min_units` (CALISMA DEGERI, kanon değil; 0 = o ölçüt kapalı).
## `requires_council.zoning.propose` = meclis yolu var mı (false: hiçbir plan gitmez); eşikler ikisi de 0 iken eski
## davranış (bayrak tek başına karar verir) BİT-BİT korunur. Büyüklük = parsel sayısı >= min_parcels YA DA önizlemedeki
## toplam birim >= min_units (aynı formül: `EconomySystem.plan_preview`). Meclis yalnız koşulu değiştirir (CAN-03).

const AXIS := "growth_vs_preservation"
const MEMBERS: Array[String] = [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]
const RIGGED_AXES := {"zoning": {"zone.mixed": {"growth_vs_preservation": -1000}}}
const ENABLED := {"decision": {"unplanned_land_enabled": 1}}
const MIXED := &"zone.mixed"


## `min_parcels`/`min_units` < 0: anahtar hiç yazılmaz (eski veri biçimi).
func _edit(min_parcels: int, min_units: int = 0, flag: bool = true) -> Callable:
	return func(f: Dictionary) -> void:
		f["council"]["proposal_axes"] = RIGGED_AXES
		f["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {}}}
		f["council"]["requires_council"]["zoning.propose"] = flag
		if min_parcels >= 0:
			f["council"]["plan_council_min_parcels"] = min_parcels
		if min_units >= 0:
			f["council"]["plan_council_min_units"] = min_units


func _stance(h: PoliticsHandle, yes: bool) -> void:
	for member in MEMBERS:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"][AXIS] = -1000 if yes else 1000


func _ids(h: PoliticsHandle, from: int, count: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i in count:
		out.append(h.facade.parcel_ids()[from + i])
	return out


func _propose(h: PoliticsHandle, ids: PackedInt64Array) -> CommandResult:
	return h.facade.submit_command(SimCommand.zoning_propose(ids, MIXED))


func _plan(h: PoliticsHandle, id: int) -> Dictionary:
	return h.economy.plan_state(h.state(), id)


func _votes(h: PoliticsHandle) -> Array:
	return pol(h)["council"]["votes"]


func _events(h: PoliticsHandle, message_key: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in h.facade.events_since(0):
		if e.message_key == message_key:
			out.append(e)
	return out


func test_plan_below_the_parcel_threshold_goes_direct_without_a_vote() -> void:
	var h := handle(ENABLED, 6, SEED, _edit(3))
	_stance(h, false)  # meclis olsaydı reddederdi: direkt yol bunu bile görmez
	var ids := _ids(h, 0, 2)
	assert_bool(h.facade.plan_preview(ids, MIXED).council_required).override_failure_message("küçük plan meclise gitmez") \
		.is_false()
	_propose(h, ids)
	h.facade.advance(1)
	assert_str(String(_plan(h, ids[0])["state"])).is_equal("proposed")
	h.facade.advance(5)
	for id in ids:
		assert_str(String(_plan(h, id)["state"])).is_equal("planned")
		assert_str(String(_plan(h, id)["zone"])).is_equal(String(MIXED))
	assert_int(_votes(h).size()).override_failure_message("oylama açılmamalı").is_equal(0)
	assert_int(_events(h, &"event.zoning.plan_rejected").size()).is_equal(0)


func test_plan_at_the_parcel_threshold_goes_to_the_council_and_records_why() -> void:
	var h := handle(ENABLED, 6, SEED, _edit(3))
	_stance(h, true)
	var ids := _ids(h, 0, 3)
	assert_bool(h.facade.plan_preview(ids, MIXED).council_required).is_true()
	var result := _propose(h, ids)
	h.facade.advance(2)
	assert_int(_votes(h).size()).is_equal(1)
	assert_int(CouncilEngine.pending_vote_for_parcel(h.state(), ids[0])).is_greater(0)
	assert_str(String(_plan(h, ids[0])["state"])).override_failure_message("oylama bitmeden yürürlük yok") \
		.is_equal("unplanned")
	var route: Dictionary = (_votes(h)[0]["proposal"] as Dictionary).get("route", {})
	assert_str(String(route.get("reason", ""))).is_equal("plan.council_large")
	assert_int(int(route.get("parcels", -1))).is_equal(3)
	assert_int(int(route.get("min_parcels", -1))).is_equal(3)
	h.facade.advance(30)
	for id in ids:
		assert_str(String(_plan(h, id)["state"])).is_equal("planned")
		assert_int(_plan(h, id)["command_id"]).is_equal(result.command_id)


func test_large_plan_rejected_by_the_council_records_plan_rejected_and_builds_nothing() -> void:
	var h := handle(ENABLED, 6, SEED, _edit(3))
	_stance(h, false)
	var ids := _ids(h, 0, 3)
	var result := _propose(h, ids)
	h.facade.advance(40)
	for id in ids:
		assert_str(String(_plan(h, id)["state"])).is_equal("plan_rejected")
		assert_int(_plan(h, id)["rejected_command_id"]).is_equal(result.command_id)
	var rejected := _events(h, &"event.zoning.plan_rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0].command_id).is_equal(result.command_id)
	assert_int(EconomyQuery.totals(h.state()).get("approvals", 0)).override_failure_message("ret bina yaratmaz (CAN-03)") \
		.is_equal(0)


func test_units_threshold_decides_by_the_preview_total_not_the_parcel_count() -> void:
	var probe := handle(ENABLED, 6, SEED, _edit(0, 0))
	probe.facade.advance(1)
	var one := probe.facade.plan_preview(_ids(probe, 0, 1), MIXED)
	var three := probe.facade.plan_preview(_ids(probe, 0, 3), MIXED)
	assert_bool(one.ok).is_true()
	assert_int(one.total_units).override_failure_message("önizleme birimi sıfır: test anlamsız").is_greater(0)
	assert_int(three.total_units).is_greater(one.total_units)
	# Eşik = 3 parselin toplamı: 1 parsel direkt, 3 parsel meclise.
	var h := handle(ENABLED, 6, SEED, _edit(0, three.total_units))
	h.facade.advance(1)
	assert_bool(h.facade.plan_preview(_ids(h, 0, 1), MIXED).council_required).is_false()
	assert_bool(h.facade.plan_preview(_ids(h, 0, 3), MIXED).council_required).is_true()
	_propose(h, _ids(h, 0, 3))
	h.facade.advance(2)
	var route: Dictionary = (_votes(h)[0]["proposal"] as Dictionary)["route"]
	assert_int(int(route["units"])).is_equal(three.total_units)
	assert_int(int(route["min_units"])).is_equal(three.total_units)
	var small := handle(ENABLED, 6, SEED, _edit(0, three.total_units))
	small.facade.advance(1)
	_propose(small, _ids(small, 0, 1))
	small.facade.advance(6)
	assert_int(_votes(small).size()).is_equal(0)
	assert_str(String(_plan(small, small.facade.parcel_ids()[0])["state"])).is_equal("planned")


func test_flag_false_sends_no_plan_to_the_council_whatever_the_thresholds() -> void:
	var h := handle(ENABLED, 6, SEED, _edit(1, 1, false))
	var ids := _ids(h, 0, 4)
	assert_bool(h.facade.plan_preview(ids, MIXED).council_required).is_false()
	_propose(h, ids)
	h.facade.advance(6)
	assert_int(_votes(h).size()).is_equal(0)
	assert_str(String(_plan(h, ids[0])["state"])).is_equal("planned")


func test_zero_or_absent_thresholds_keep_the_old_flag_behaviour() -> void:
	# `state_hash` siyaset `config_digest`ini (ham veri) içerir: anahtar yok vs 0 farklı özet verir; davranış eşitliği
	# ekonomi durumu + oylama kaydıyla karşılaştırılır. GOLDEN A/B (veri dosyası DEĞİŞMEDİ) m2_query_test'te.
	var hashes: Array[String] = []
	for edit: Callable in [_edit(-1, -1), _edit(0, 0)]:  # anahtar yok / açıkça 0
		var h := handle(ENABLED, 6, SEED, edit)
		_stance(h, true)
		assert_bool(h.facade.plan_preview(_ids(h, 0, 1), MIXED).council_required).is_true()
		_propose(h, _ids(h, 0, 1))  # tek parsel bile meclise gider (eski: bayrak true)
		h.facade.advance(40)
		assert_int(_votes(h).size()).is_equal(1)
		assert_bool((_votes(h)[0]["proposal"] as Dictionary).has("route")).override_failure_message(
			"eşik kapalıyken oylamaya yeni anahtar yazılmaz (kayıt/hash eşit)").is_false()
		hashes.append(StateHash.of([EconomyState.data(h.state()), _votes(h)]))
	assert_str(hashes[0]).is_equal(hashes[1])


func test_a_small_plan_under_active_thresholds_matches_the_no_council_run() -> void:
	# Eşik açık ama plan küçük: ekonomi durumu ve oylama kaydı, meclis hiç yokmuş (flag false) koşuyla eşit (yeni durum
	# yalnız tetiklenince). Tam `state_hash` config_digest yüzünden (ham veri farkı) karşılaştırılmaz.
	var gated := handle(ENABLED, 6, SEED, _edit(5))
	var plain := handle(ENABLED, 6, SEED, _edit(-1, -1, false))
	for h in [gated, plain]:
		_propose(h, _ids(h, 0, 2))
		h.facade.advance(30)
	assert_str(StateHash.of([EconomyState.data(gated.state()), _votes(gated)])) \
		.is_equal(StateHash.of([EconomyState.data(plain.state()), _votes(plain)]))
	assert_int(_votes(gated).size()).is_equal(0)


func test_pending_vote_still_blocks_an_overlapping_small_plan() -> void:
	var h := handle(ENABLED, 6, SEED, _edit(3))
	_stance(h, true)
	_propose(h, _ids(h, 0, 3))
	h.facade.advance(2)
	var again := _propose(h, _ids(h, 1, 1))
	assert_bool(again.is_rejected()).override_failure_message("bekleyen oylamalı parsele yeni plan reddedilir").is_true()


func test_threshold_path_is_deterministic_and_survives_save_load() -> void:
	var a := handle(ENABLED, 6, SEED, _edit(3))
	var b := handle(ENABLED, 6, SEED, _edit(3))
	var c := handle(ENABLED, 6, SEED, _edit(3))
	for h in [a, b, c]:
		_stance(h, false)
		_propose(h, _ids(h, 0, 3))  # büyük: meclise
		_propose(h, _ids(h, 3, 1))  # küçük: direkt
	a.facade.advance(60)
	b.facade.advance(60)
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())
	c.facade.advance(5)  # oylama açık, küçük plan yürürlükte
	var bytes := c.facade.export_save()
	var d := handle(ENABLED, 6, SEED, _edit(3))
	var loaded := d.facade.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	d.facade.advance(55)
	assert_str(d.facade.state_hash()).is_equal(a.facade.state_hash())
	assert_str(String(_plan(a, a.facade.parcel_ids()[0])["state"])).is_equal("plan_rejected")
	assert_str(String(_plan(a, a.facade.parcel_ids()[3])["state"])).is_equal("planned")


func test_invalid_threshold_values_are_rejected_by_the_config_validator() -> void:
	for bad: Variant in [-1, "3", 2.5, true]:
		var cfg := pol_mutated(func(f: Dictionary) -> void: f["council"]["plan_council_min_parcels"] = bad)
		assert_bool(cfg.is_valid()).override_failure_message("plan_council_min_parcels=%s geçersiz sayılmalı" % str(bad)) \
			.is_false()
		var cfg2 := pol_mutated(func(f: Dictionary) -> void: f["council"]["plan_council_min_units"] = bad)
		assert_bool(cfg2.is_valid()).override_failure_message("plan_council_min_units=%s geçersiz sayılmalı" % str(bad)) \
			.is_false()
	var ok := pol_valid(func(f: Dictionary) -> void:
		f["council"]["plan_council_min_parcels"] = 8
		f["council"]["plan_council_min_units"] = 0)
	assert_int(ok.council["plan_council_min_parcels"]).is_equal(8)
