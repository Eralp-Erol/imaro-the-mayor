extends SimTestBase
## T-027 ölçüt 3 · Mock/gerçek DTO ŞEKİL eşliği: aynı komut dizisi `MockSimFacade` ve `SimFacadeImpl` üzerinde aynı
## alan kümesini ve türlerini üretir (değerler farklı olabilir). Mock'ta dolu olup gerçekte kurulmamış bölümler
## `available=false` döner. UI'nin mock ile yazdığı kod gerçeğe geçince şekil sürprizi yaşamaz.

const S := preload("res://tests/contracts/contract_test_support.gd")
const HORIZON := 12
## Açık uçlu sözlükler: yalnız sözlük olmaları beklenir, içerik karşılaştırılmaz.
const OPEN_ENDED: Array[String] = ["extensions", "args", "params"]


## İki değerin ŞEKLİ (alan kümesi + tür) farkları. null = isteğe bağlı (her şeyle eşleşir); boş dizi =
## karşılaştırılamaz.
static func shape_diff(a: Variant, b: Variant, path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if a == null or b == null:
		return out
	if typeof(a) != typeof(b):
		out.append("%s: tür %s != %s" % [path, type_string(typeof(a)), type_string(typeof(b))])
		return out
	if a is Dictionary:
		if OPEN_ENDED.has(path.get_slice(".", path.get_slice_count(".") - 1)):
			return out
		for k: Variant in a:
			if not (b as Dictionary).has(k):
				out.append("%s: alan yalnız solda: %s" % [path, k])
			else:
				out.append_array(shape_diff(a[k], b[k], "%s.%s" % [path, k]))
		for k: Variant in b:
			if not (a as Dictionary).has(k):
				out.append("%s: alan yalnız sağda: %s" % [path, k])
	elif a is Array:
		if not (a as Array).is_empty() and not (b as Array).is_empty():
			out.append_array(shape_diff(a[0], b[0], path + "[]"))
	return out


func _impl() -> SimFacadeImpl:
	return FacadeTestSupport.facade(3)


func _mock(scenario_name: String) -> MockSimFacade:
	return S.facade(scenario_name)


## Aynı komut dizisi: geçerli imar, bilinmeyen parsel, yasak fiil, bütçe önerisi, eksik parametre.
func _sequence() -> Array[SimCommand]:
	return [
		SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"),
		SimCommand.zoning_propose(PackedInt64Array([99999]), &"zone.mixed"),
		SimCommand.make(&"building.place", {"parcel_ids": PackedInt64Array([1])}),
		SimCommand.budget_propose({&"budget.line.roads": 50000}),
		SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}),
	]


func _run(f: SimFacade) -> Array[CommandResult]:
	var results: Array[CommandResult] = []
	for c in _sequence():
		results.append(f.submit_command(c))
	f.advance(HORIZON)
	return results


# --- Yardımcının kendisi başarısız olabilmeli ---

func test_shape_diff_detects_missing_fields_and_type_changes() -> void:
	assert_array(shape_diff({"a": 1}, {"a": 1}, "x")).is_empty()
	assert_array(shape_diff({"a": 1}, {"a": 1, "b": 2}, "x")).is_not_empty()
	assert_array(shape_diff({"a": 1, "b": 2}, {"a": 1}, "x")).is_not_empty()
	assert_array(shape_diff({"a": 1}, {"a": 1.0}, "x")).override_failure_message("int != float").is_not_empty()
	assert_array(shape_diff({"a": &"s"}, {"a": "s"}, "x")).override_failure_message("StringName != String").is_not_empty()
	assert_array(shape_diff({"a": [1]}, {"a": [1.5]}, "x")).is_not_empty()
	assert_array(shape_diff({"a": [1]}, {"a": []}, "x")).override_failure_message("boş dizi karşılaştırılamaz").is_empty()
	assert_array(shape_diff({"a": null}, {"a": {"k": 1}}, "x")).override_failure_message("null isteğe bağlı").is_empty()
	assert_array(shape_diff({"args": {"p": 1}}, {"args": {"q": 2}}, "x")).override_failure_message("açık uçlu").is_empty()


# --- Komut sonuçları ---

func test_command_results_have_identical_shape_for_the_same_sequence() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var mock_results := _run(_mock(scenario_name))
		var real_results := _run(_impl())
		assert_int(real_results.size()).is_equal(mock_results.size())
		for i in mock_results.size():
			var diff := shape_diff(mock_results[i].to_dict(), real_results[i].to_dict(), "result%d" % i)
			assert_array(diff).override_failure_message("%s komut %d: %s" % [scenario_name, i, diff]).is_empty()


func test_shared_command_semantics_agree_on_status_and_reject_keys() -> void:
	# Şekil eşliği değerlerden bağımsızdır; AMA mock'un sözleşme anlamı (CAN-03, ret anahtarları) gerçekle çelişmemeli.
	var mock_results := _run(_mock(S.SCENARIO_POSITIVE))
	var real_results := _run(_impl())
	for i in [0, 1, 2, 4]:
		assert_str(String(real_results[i].status)).override_failure_message("komut %d" % i) \
			.is_equal(String(mock_results[i].status))
		assert_str(String(real_results[i].reason_key)).is_equal(String(mock_results[i].reason_key))
	# Bütçe: mock'ta kurulu (queued), gerçekte kurulmamış (precondition) -- bilinçli fark.
	assert_str(String(mock_results[3].status)).is_equal("queued")
	assert_str(String(real_results[3].reason_key)).is_equal(String(CommandResult.REJECT_PRECONDITION))


# --- Snapshot, parsel, olay, gerekçe ---

func test_snapshot_clock_parcel_and_event_shapes_match() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var mock := _mock(scenario_name)
		var real := _impl()
		_run(mock)
		_run(real)
		var snap_diff := shape_diff(mock.snapshot().to_dict(), real.snapshot().to_dict(), "snapshot")
		assert_array(snap_diff).override_failure_message("%s: %s" % [scenario_name, snap_diff]).is_empty()
		var mock_parcel := mock.parcel_views(PackedInt64Array([1]))[0].to_dict()
		var real_parcel := real.parcel_views(PackedInt64Array([1]))[0].to_dict()
		assert_array(shape_diff(mock_parcel, real_parcel, "parcel")).is_empty()
		var mock_events := mock.events_since(0)
		var real_events := real.events_since(0)
		assert_array(real_events).is_not_empty()
		assert_array(mock_events).is_not_empty()
		var compared := 0
		for kind in [SimEvent.KIND_COMMAND_APPLIED, SimEvent.KIND_COMMAND_REJECTED, SimEvent.KIND_PARCEL_CHANGED]:
			var mock_of_kind := mock_events.filter(func(e: SimEvent) -> bool: return e.kind == kind)
			var real_of_kind := real_events.filter(func(e: SimEvent) -> bool: return e.kind == kind)
			if mock_of_kind.is_empty() or real_of_kind.is_empty():
				continue
			compared += 1
			var event_diff := shape_diff(mock_of_kind[0].to_dict(), real_of_kind[0].to_dict(), String(kind))
			assert_array(event_diff).override_failure_message("%s: %s" % [scenario_name, event_diff]).is_empty()
		assert_int(compared).override_failure_message("%s: karşılaştırılan olay türü yok" % scenario_name).is_greater(0)
		var mock_applied := mock_events.filter(func(e: SimEvent) -> bool: return e.kind == SimEvent.KIND_COMMAND_APPLIED)
		var real_applied := real_events.filter(func(e: SimEvent) -> bool: return e.kind == SimEvent.KIND_COMMAND_APPLIED)
		if not mock_applied.is_empty():
			assert_dict(real_applied[0].args).is_equal(mock_applied[0].args)
		assert_array(SimContractChecks.check_facade(mock)).is_empty()
		assert_array(SimContractChecks.check_facade(real)).is_empty()


func test_reason_shape_matches_mock_reason_with_all_fields() -> void:
	var mock := _mock(S.SCENARIO_POSITIVE)
	mock.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	mock.advance(30)
	var mock_reason: ReasonRecord = mock.reasons_for(&"parcel.1")[0]
	var real := _impl()
	var st := real.game_state()
	var parent := st.record_reason(&"actor.group.2", &"decision.group.support", [{"name": &"reason.factor.jobs_access",
		"value": 400, "weight": 800}], 100, &"", PackedStringArray(["parcel.1"]))
	st.record_reason(&"actor.investor.1", &"decision.investor.develop", [
		{"name": &"reason.factor.demand", "value": 800, "weight": 500, "is_estimate": true},
		{"name": &"reason.factor.expected_return", "value": 300, "weight": 1000},
	], 200, &"x", PackedStringArray(["parcel.1", "command.1"]), PackedInt64Array([parent]))
	var real_reason: ReasonRecord = real.reasons_for(&"parcel.1")[1]
	var diff := shape_diff(mock_reason.to_dict(), real_reason.to_dict(), "reason")
	assert_array(diff).override_failure_message(str(diff)).is_empty()
	assert_array(shape_diff(mock_reason.factors[0].to_dict(), real_reason.factors[0].to_dict(), "factor")).is_empty()
	assert_bool(real_reason.is_consistent()).is_true()
	assert_bool(mock_reason.is_consistent()).is_true()
	assert_array(shape_diff(mock_reason.actor.to_dict(), real_reason.actor.to_dict(), "actor")).is_empty()


func test_dto_dicts_are_hashable_like_the_mock_ones() -> void:
	# Her gerçek DTO sözlüğü StateHash'e girebilir (ADR-0005 §3: tekil Vector2 / tipli Array yok).
	var real := _impl()
	_run(real)
	assert_str(assert_hash(StateHash.of(SimContractChecks.observable_state(real)))).is_not_empty()


# --- Kurulmamış sistemler ---

func test_sections_the_mock_fills_but_the_sim_has_not_built_report_unavailable() -> void:
	var real_snapshot := _impl().snapshot()
	var seen := {"budget": false, "council": false, "groups": false}
	for scenario_name in S.ALL_SCENARIOS:
		var mock_snapshot := _mock(scenario_name).snapshot()
		seen["budget"] = seen["budget"] or not mock_snapshot.budget.lines.is_empty()
		seen["council"] = seen["council"] or not mock_snapshot.council.blocs.is_empty()
		seen["groups"] = seen["groups"] or not mock_snapshot.group_reactions.is_empty()
	for section: String in seen:
		assert_bool(seen[section]).override_failure_message("mock %s'i hiçbir senaryoda doldurmuyor" % section).is_true()
		assert_bool(real_snapshot.extensions["x.sim.available." + section]).is_false()
	assert_bool(real_snapshot.extensions["x.sim.available.parcels"]).is_true()
	assert_array(real_snapshot.budget.lines).is_empty()
	assert_array(real_snapshot.council.blocs).is_empty()
	assert_array(real_snapshot.group_reactions).is_empty()
	var council_diff := shape_diff(_mock(S.SCENARIO_COUNCIL).snapshot().to_dict(), real_snapshot.to_dict(), "snapshot")
	assert_array(council_diff).is_empty()


func test_real_facade_exposes_every_mock_method() -> void:
	# SimFacade @abstract: eksik metod ayrıştırma hatasıdır; ayrıca açık denetim.
	var real := _impl()
	for method in ["provenance", "current_tick", "speed", "available_speeds", "set_speed", "advance", "validate_command",
			"submit_command", "snapshot", "parcel_ids", "parcel_views", "events_since", "last_event_seq",
			"first_retained_event_seq", "reasons_for", "reason", "contract_version", "is_mock"]:
		assert_bool(real.has_method(method)).override_failure_message("eksik: %s" % method).is_true()
