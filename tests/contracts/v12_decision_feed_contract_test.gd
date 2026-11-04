extends GdUnitTestSuite
## T-045 (B-001/B-002 sim tarafı) sözleşme genişlemesi, sürüm 1.2 (ADR-0005 Ek D): `ParcelView.decision*` (kalıcı karar
## özeti) ve `SimFacade.parcel_changes_since` / `ParcelChangeFeed`. Geriye uyum, kayıpsız dönüşüm, uyum kontrolü, taban
## varsayılan ve mock paritesi.

const S := preload("res://tests/contracts/contract_test_support.gd")


## Soyut tabanın varsayılanlarını sınamak için en küçük somut facade (yalnız zorunlu metodlar).
class BareFacade:
	extends SimFacade

	func provenance() -> StringName:
		return SimContract.PROVENANCE_MOCK

	func current_tick() -> int:
		return 42

	func speed() -> int:
		return SPEED_PAUSED

	func available_speeds() -> PackedInt32Array:
		return PackedInt32Array([SPEED_PAUSED])

	func set_speed(_level: int) -> bool:
		return false

	func advance(_ticks: int) -> int:
		return 0

	func validate_command(command: SimCommand) -> CommandResult:
		return CommandResult.rejected(command, CommandResult.REJECT_UNKNOWN_KIND, {}, 42, provenance())

	func submit_command(command: SimCommand) -> CommandResult:
		return CommandResult.rejected(command, CommandResult.REJECT_UNKNOWN_KIND, {}, 42, provenance())

	func snapshot() -> SimSnapshot:
		return SimSnapshot.new()

	func parcel_ids(_region_code: StringName = &"") -> PackedInt64Array:
		return PackedInt64Array()

	func parcel_views(_ids: PackedInt64Array) -> Array[ParcelView]:
		return []

	func events_since(_after_seq: int, _max_count: int = 0) -> Array[SimEvent]:
		return []

	func last_event_seq() -> int:
		return 0

	func first_retained_event_seq() -> int:
		return 1

	func reasons_for(_subject_ref: StringName) -> Array[ReasonRecord]:
		return []

	func reason(_reason_id: int) -> ReasonRecord:
		return null


func _decided(decision: StringName, code: StringName, tick: int, reason_id: int) -> ParcelView:
	var p := ParcelView.new()
	p.id = 7
	p.decision = decision
	p.decision_code = code
	p.decision_tick = tick
	p.decision_reason_id = reason_id
	return p


func _approved_built() -> ParcelView:
	var p := _decided(ParcelView.DECISION_APPROVED, &"approved", 12, 3)
	p.development = ParcelView.DEVELOPMENT_BUILT
	p.use = ParcelView.USE_RESIDENTIAL
	p.units = 6
	p.progress_pm = 1000
	p.developed_by_sim = true
	return p


# --- Sürüm ---

func test_contract_version_is_at_least_1_2_and_stays_compatible() -> void:
	assert_bool(SimContract.VERSION_MINOR >= 2).is_true()  # 1.3 (T-042) 1.2 belgelerini kabul eder
	assert_bool(SimContract.is_compatible("1.1")).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()


# --- ParcelView karar özeti ---

func test_decision_fields_default_to_none_and_old_documents_stay_loadable() -> void:
	var p := ParcelView.new()
	assert_str(String(p.decision)).is_equal("")
	assert_str(String(p.decision_code)).is_equal("")
	assert_int(p.decision_tick).is_equal(-1)
	assert_int(p.decision_reason_id).is_equal(0)
	var old := ParcelView.from_dict({"id": 9, "development": "built", "use": "residential", "units": 3})
	assert_str(String(old.decision)).is_equal("")
	assert_int(old.decision_tick).is_equal(-1)
	assert_int(old.decision_reason_id).is_equal(0)


func test_decision_fields_roundtrip_losslessly_and_change_the_dto_hash() -> void:
	var p := _approved_built()
	assert_bool(ParcelView.from_dict(p.to_dict()).same_as(p)).is_true()
	var via_json := ParcelView.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_bool(via_json.same_as(p)).override_failure_message("JSON turu kayıplı").is_true()
	assert_str(String(via_json.decision)).is_equal("approved")
	assert_str(String(via_json.decision_code)).is_equal("approved")
	assert_int(via_json.decision_tick).is_equal(12)
	assert_int(via_json.decision_reason_id).is_equal(3)
	var base := StateHash.of(p.to_dict())
	for edit: Callable in [
			func(v: ParcelView) -> void: v.decision = ParcelView.DECISION_DECLINED,
			func(v: ParcelView) -> void: v.decision_code = &"demand_too_low",
			func(v: ParcelView) -> void: v.decision_tick += 1,
			func(v: ParcelView) -> void: v.decision_reason_id += 1]:
		var q := _approved_built()
		edit.call(q)
		assert_str(StateHash.of(q.to_dict())).is_not_equal(base)


func test_decision_check_accepts_consistent_parcels() -> void:
	var none := ParcelView.new()
	none.id = 1
	var declined := _decided(ParcelView.DECISION_DECLINED, &"demand_too_low", 30, 0)  # gerekçe budanmış: 0 geçerli
	declined.id = 2
	var views: Array[ParcelView] = [none, declined, _approved_built()]
	assert_array(SimContractChecks.check_parcel_decisions(views)).is_empty()


func test_decision_check_catches_each_inconsistency() -> void:
	var cases := {
		"unknown_decision": func(p: ParcelView) -> void: p.decision = &"maybe",
		"approved_with_decline_code": func(p: ParcelView) -> void: p.decision_code = &"demand_too_low",
		"approved_on_vacant": func(p: ParcelView) -> void:
			p.development = ParcelView.DEVELOPMENT_VACANT
			p.use = ParcelView.USE_NONE
			p.units = 0
			p.progress_pm = 0
			p.developed_by_sim = false,
		"declined_on_built": func(p: ParcelView) -> void:
			p.decision = ParcelView.DECISION_DECLINED
			p.decision_code = &"return_too_low",
		"declined_with_approved_code": func(p: ParcelView) -> void:
			p.decision = ParcelView.DECISION_DECLINED
			p.development = ParcelView.DEVELOPMENT_VACANT
			p.use = ParcelView.USE_NONE
			p.units = 0
			p.progress_pm = 0,
		"decision_without_tick": func(p: ParcelView) -> void: p.decision_tick = -1,
		"negative_reason": func(p: ParcelView) -> void: p.decision_reason_id = -2,
		"none_with_leftovers": func(p: ParcelView) -> void: p.decision = ParcelView.DECISION_NONE,
	}
	for label: String in cases:
		var p := _approved_built()
		(cases[label] as Callable).call(p)
		var views: Array[ParcelView] = [p]
		assert_array(SimContractChecks.check_parcel_decisions(views)) \
			.override_failure_message("yakalanmadı: %s" % label).is_not_empty()


# --- ParcelChangeFeed ---

func test_change_feed_roundtrips_and_defaults_to_incomplete() -> void:
	var feed := ParcelChangeFeed.new()
	assert_bool(feed.complete).is_false()
	assert_int(feed.ids.size()).is_equal(0)
	feed.complete = true
	feed.ids = PackedInt64Array([3, 9, 12])
	feed.up_to_tick = 77
	feed.epoch = 2
	feed.provenance = SimContract.PROVENANCE_SIM
	var again := ParcelChangeFeed.from_dict(feed.to_dict())
	assert_bool(again.same_as(feed)).is_true()
	var via_json := ParcelChangeFeed.from_dict(JSON.parse_string(JSON.stringify(feed.to_dict())))
	assert_bool(via_json.same_as(feed)).override_failure_message("JSON turu kayıplı").is_true()
	assert_bool(via_json.complete).is_true()
	assert_int(via_json.ids.size()).is_equal(3)
	assert_int(via_json.up_to_tick).is_equal(77)
	assert_int(via_json.epoch).is_equal(2)
	assert_str(StateHash.of(feed.to_dict())).is_not_empty()


func test_base_facade_default_is_not_abstract_and_says_incomplete_with_no_ids() -> void:
	var f := BareFacade.new()
	var feed := f.parcel_changes_since(0)
	assert_bool(feed.complete).is_false()
	assert_int(feed.ids.size()).is_equal(0)
	assert_int(feed.up_to_tick).is_equal(42)
	assert_str(String(feed.provenance)).is_equal("mock")


# --- Mock paritesi ---

func test_mock_decision_fields_follow_the_scenario_and_pass_the_checks() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	f.submit_command(SimCommand.zoning_propose(S.ids([1]), &"zone.mixed"))
	var before := f.parcel_views(S.ids([1]))[0]
	assert_str(String(before.decision)).is_equal("")
	assert_int(before.decision_tick).is_equal(-1)
	f.advance(5)  # karar etkisi 3. tick'te (+ komut 1 tick)
	var p := f.parcel_views(S.ids([1]))[0]
	assert_str(String(p.development)).is_equal("planned")
	assert_str(String(p.decision)).is_equal("approved")
	assert_str(String(p.decision_code)).is_equal("approved")
	assert_int(p.decision_tick).is_greater(0)
	assert_int(p.decision_reason_id).is_greater(0)
	assert_object(f.reason(p.decision_reason_id)).is_not_null()
	assert_array(SimContractChecks.check_parcel_decisions(f.parcel_views(f.parcel_ids()))).is_empty()
	assert_array(SimContractChecks.check_parcels(f, f.snapshot())).is_empty()


func test_mock_declined_scenario_reports_a_declined_vacant_parcel() -> void:
	var f := S.facade(S.SCENARIO_DECLINED)
	f.submit_command(SimCommand.zoning_propose(S.ids([1]), &"zone.mixed"))
	f.advance(6)
	var p := f.parcel_views(S.ids([1]))[0]
	assert_str(String(p.development)).is_equal("vacant")
	assert_str(String(p.decision)).is_equal("declined")
	assert_str(String(p.decision_code)).is_not_equal("approved")
	assert_int(p.decision_reason_id).is_greater(0)
	assert_array(SimContractChecks.check_parcels(f, f.snapshot())).is_empty()


func test_mock_change_feed_lists_changed_parcels_and_is_independent_of_event_retention() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var start := f.parcel_changes_since(-1)
	assert_bool(start.complete).is_true()
	assert_int(start.ids.size()).is_equal(0)
	assert_int(start.up_to_tick).is_equal(f.current_tick())
	f.submit_command(SimCommand.zoning_propose(S.ids([1]), &"zone.mixed"))
	f.advance(5)
	var mid := f.parcel_changes_since(start.up_to_tick)
	assert_bool(mid.complete).is_true()
	assert_array(Array(mid.ids)).is_equal([1])
	assert_int(mid.up_to_tick).is_equal(f.current_tick())
	assert_int(mid.epoch).is_equal(start.epoch)
	var quiet := f.parcel_changes_since(mid.up_to_tick)
	assert_bool(quiet.complete).is_true()
	assert_int(quiet.ids.size()).is_equal(0)
	assert_str(String(quiet.provenance)).is_equal("mock")
	var future := f.parcel_changes_since(f.current_tick() + 5)
	assert_bool(future.complete).override_failure_message("gelecekten sorgu eksik sayılır").is_false()
