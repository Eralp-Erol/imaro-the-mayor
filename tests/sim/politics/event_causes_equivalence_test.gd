extends PoliticsTestBase
## Haftalık siyaset taraması hızlandırması (2026-11-01, ADR önerisi §1 Seçenek A): `EventCauses.region_projects`
## tarama başına tek parsel geçişi, `recent_declines`/`_region_of_event` kopyasız okuma. DAVRANIŞ DEĞİŞMEZ:
## buradaki REFERANS kopyalar eski (kesim başına tam tarama, derin kopyalı) kodun aynısıdır; yeni yol onlarla
## bit-bit aynı çıktıyı vermelidir (birkaç tohum, eşit reason_id + farklı parsel sırası kenarı dahil).

const M := preload("res://tests/sim/m2_support.gd")
const SEEDS: Array[int] = [20261020, 7, 99001]
const REF_DAYS := 70


## ESKİ `EventCauses.region_projects` (referans kopya; değiştirmeyin).
static func ref_region_projects(state: GameState, ctx: PoliticsContext, exposure: Dictionary) -> Dictionary:
	var out := {"reason_ids": PackedInt64Array(), "parcel_refs": PackedStringArray()}
	var d := EconomyState.data(state)
	if d.is_empty():
		return out
	var stage: PackedByteArray = d["stage"]
	var reason_column: PackedInt64Array = d["reason_id"]
	var found: Array = []
	for i in stage.size():
		var skipped: bool = stage[i] == EconomyState.STAGE_VACANT or stage[i] == EconomyState.STAGE_TAKEN
		if skipped or reason_column[i] < 1 or not exposure.has(ctx.regions.code_at(i)):
			continue
		found.append([reason_column[i], ctx.regions.id_at(i)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var cap := int(ctx.politics.cadence["cause_cap"])
	var chosen: Array = found.slice(0, cap)
	chosen.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for pair: Array in chosen:
		out["reason_ids"].append(pair[0])
		out["parcel_refs"].append(String(SimContract.parcel_ref(pair[1])))
	return out


## ESKİ `EventCauses.recent_declines` (`find` = derin kopya).
static func ref_recent_declines(state: GameState, ctx: PoliticsContext, days: int, cap: int) -> PackedInt64Array:
	var key: String = ctx.politics.events["investor_decision"]
	var found := state.reasons.find({"decision": key, "from_tick": maxi(state.tick - days, 0)})
	var ids := PackedInt64Array()
	for rec: Dictionary in found:
		if rec["outcome"] == ReasonLog.OUTCOME_NEGATIVE:
			ids.append(rec["id"])
	return ids.slice(maxi(ids.size() - cap, 0))


## ESKİ `EventEngine._region_of_event` nedenler kısmı (`by_id` = derin kopya); bulunamazsa "".
static func ref_region_from_causes(state: GameState, ctx: PoliticsContext, causes: PackedInt64Array) -> String:
	for i in range(causes.size() - 1, -1, -1):
		var record := state.reasons.by_id(causes[i])
		for subject: String in record.get("subjects", PackedStringArray()):
			var code := ctx.regions.code_of(int(SimContract.parse_ref(StringName(subject))["id"])) \
				if subject.begins_with("parcel.") else ""
			if not code.is_empty():
				return code
	return ""


func _run(world_seed: int) -> PoliticsHandle:
	var h := M.politics_handle(M.E.regions(M.STRESS), 14, world_seed)
	var r := h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	assert_bool(r.is_rejected()).override_failure_message("imar komutu reddedildi").is_false()
	h.facade.advance(REF_DAYS)
	return h


func _exposures(ctx: PoliticsContext) -> Array[Dictionary]:
	var codes := {}
	for i in ctx.regions.count():
		codes[ctx.regions.code_at(i)] = 500
	var all_codes: Array = codes.keys()
	all_codes.sort()
	var out: Array[Dictionary] = [codes.duplicate(), {}, {"NOPE": 1}]
	for code: String in all_codes:
		out.append({code: 300})
		out.append({code: 300, "NOPE": 10})
	return out


func _same(a: Dictionary, b: Dictionary, label: String) -> void:
	assert_array(Array(a["reason_ids"])).override_failure_message("reason_ids " + label).is_equal(Array(b["reason_ids"]))
	assert_array(Array(a["parcel_refs"])).override_failure_message("parcel_refs " + label) \
		.is_equal(Array(b["parcel_refs"]))


func test_region_projects_equals_the_old_full_scan_on_real_runs_with_a_shared_scan_cache() -> void:
	var nonempty := 0
	for world_seed in SEEDS:
		var h := _run(world_seed)
		var state := h.state()
		var scan_cache := {}  # TEK tarama boyunca paylaşılan yerel önbellek (kesimler arası)
		for exposure in _exposures(h.context):
			var want := ref_region_projects(state, h.context, exposure)
			_same(EventCauses.region_projects(state, h.context, exposure, scan_cache), want, "cache seed %d" % world_seed)
			_same(EventCauses.region_projects(state, h.context, exposure), want, "nocache seed %d" % world_seed)
			if not (want["reason_ids"] as PackedInt64Array).is_empty():
				nonempty += 1
	assert_int(nonempty).override_failure_message("senaryo hiç neden üretmedi: test boş").is_greater(3)


func test_region_projects_ties_on_reason_id_break_by_parcel_id_and_respect_the_cap_for_random_columns() -> void:
	var h := _run(SEEDS[0])
	var state := h.state()
	var d := EconomyState.data(state)
	var stage: PackedByteArray = d["stage"]
	var reasons: PackedInt64Array = d["reason_id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var exposures := _exposures(h.context)
	for trial in 24:
		for i in stage.size():  # az sayıda farklı reason_id => bol eşitlik; bazı parseller boş/alınmış/gerekçesiz
			stage[i] = rng.randi_range(0, 5)
			reasons[i] = rng.randi_range(-1, 4) if trial % 2 == 0 else rng.randi_range(0, 1)
		d["stage"] = stage
		d["reason_id"] = reasons
		var scan_cache := {}
		for exposure in exposures:
			var want := ref_region_projects(state, h.context, exposure)
			_same(EventCauses.region_projects(state, h.context, exposure, scan_cache), want, "trial %d" % trial)


func test_region_projects_cache_is_local_to_the_scan_and_never_enters_state_or_hash() -> void:
	var h := _run(SEEDS[1])
	var state := h.state()
	var before := state_hash_of(state)
	var scan_cache := {}
	var first := EventCauses.region_projects(state, h.context, _exposures(h.context)[0], scan_cache)
	assert_str(state_hash_of(state)).is_equal(before)
	# Yeni tarama (yeni önbellek) sütun değişimini görür; eski önbellek yalnız kendi taramasına aittir.
	var d := EconomyState.data(state)
	var reasons: PackedInt64Array = d["reason_id"]
	for i in reasons.size():
		reasons[i] = 0
	d["reason_id"] = reasons
	var fresh := EventCauses.region_projects(state, h.context, _exposures(h.context)[0])
	assert_array(Array(fresh["reason_ids"])).is_empty()
	assert_bool((first["reason_ids"] as PackedInt64Array).is_empty()).override_failure_message(
		"sınama anlamsız: ilk sonuç boş").is_false()


func test_recent_declines_equals_the_old_find_based_version() -> void:
	for world_seed in SEEDS:
		var h := _run(world_seed)
		var state := h.state()
		var key: String = h.context.politics.events["investor_decision"]
		var rng := RandomNumberGenerator.new()
		rng.seed = world_seed
		for k in 40:  # olumlu/olumsuz karışık, başka karar anahtarlı kayıtlar; tick'ler geçmişten bugüne
			var decision: Variant = key if k % 3 != 0 else &"decision.other"
			var value := rng.randi_range(0, 2000)
			state.reasons.record(maxi(state.tick - rng.randi_range(0, 60), 0), &"actor.investor.1", decision,
				[{"name": &"yield", "value": value, "weight": 1000}], 1000, &"t", PackedStringArray(["parcel.%d" % (k + 1)]))
		var nonempty := 0
		for days in [0, 3, 14, 28, 120]:
			for cap in [0, 1, 3, 8]:
				var want := ref_recent_declines(state, h.context, days, cap)
				var got := EventCauses.recent_declines(state, h.context, days, cap)
				assert_array(Array(got)).override_failure_message("days %d cap %d" % [days, cap]).is_equal(Array(want))
				nonempty += 1 if not want.is_empty() else 0
		assert_int(nonempty).override_failure_message("hiç olumsuz karar yok: test boş").is_greater(0)


func test_region_of_event_cause_lookup_equals_the_old_by_id_version_including_pruned_causes() -> void:
	var h := _run(SEEDS[0])
	var state := h.state()
	var last := state.reasons.last_id()
	var first := state.reasons.first_id()
	assert_int(last).is_greater(first)
	var bloc := {"hot_region": ""}
	var checked := 0
	for start in range(maxi(first - 2, 1), last + 3, maxi(int((last - first) / 40.0), 1)):
		var causes := PackedInt64Array([start, mini(start + 1, last), last, last + 5, 0])
		var want := ref_region_from_causes(state, h.context, causes)
		var got := EventEngine._region_of_event(state, h.context, bloc, causes)
		if not want.is_empty():  # nedenlerden bölge bulundu: yeni yol da aynısını vermeli
			assert_str(got).override_failure_message("start %d" % start).is_equal(want)
			checked += 1
	assert_int(checked).override_failure_message("hiçbir nedenden bölge bulunamadı: test boş").is_greater(0)
