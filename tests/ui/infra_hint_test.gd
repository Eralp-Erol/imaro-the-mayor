extends GdUnitTestSuite
## D-008 ipucu: altyapı yetmediği için yatırımcı gelmeyen parselde oyuncu NEDENİ ve ne yapacağını okur (SIM-12).
## Gerçek ekonomi + gerçek yol/imar komutları (PlayableEconomy dar kapasite); metin yalnız sim ret kodundan türer.
## Bildirim şeridi: altyapı vazgeçmeleri tek özet satırı; sentetik olaylarla.

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const BIG_PARCEL := 500
const BIG_UNITS := 4000


func before_test() -> void:
	M2Results.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _views() -> Array[ParcelView]:
	var out := E.views()
	var v := ParcelView.new()
	v.id = BIG_PARCEL
	v.region_code = P.CODE_A
	v.center = Vector2(100.0, 2000.0)
	v.area_m2 = 1800
	v.zone = &"zone.residential"
	v.land_value = 1000
	out.append(v)
	return out


func _facade() -> SimFacadeImpl:
	var stock := ListStockSource.create([{"parcel_id": BIG_PARCEL, "use": "residential", "units": BIG_UNITS, "owner": 1}])
	var base := {"decision": {"unplanned_land_enabled": 1, "priority_review_enabled": 1, "max_reviews_per_tick": 8}}
	var cfg := PlayableEconomy.config_for(_views(), stock, PlayableEconomy._merge(base, {}))
	var handle := EconomyBootstrap.create(P.SEED, ListParcelSource.create(&"infra.hint", _views()), cfg, stock)
	var ctx := PublicWorksContext.create(P.network(), RoadDraftRules.new(), PublicWorksConfig.load_default())
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	return E.f({"facade": handle.facade})


## Gerçek akış: panel öneri anında izlemeye başlar (karar öneri SONRASI sayılır), sonra gün ilerler.
func _open(f: SimFacadeImpl) -> M2Results:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1600, 900)
	hud.refresh()
	auto_free(hud)
	var results := M2Results.attach(hud, f)
	f.advance(20)
	assert_bool(E.plan(f, E.NEAR_A).is_rejected()).is_false()
	var ids := PackedInt64Array()
	for id in E.NEAR_A:
		ids.append(id)
	results.track_parcels(ids)
	return results


func _days(results: M2Results, days: int) -> M2ResultPanel:
	results.facade.advance(days)
	results.hud.refresh()
	return results.results_panel()


func test_plan_without_road_shows_infrastructure_cause_and_road_hint() -> void:
	var results := _open(_facade())
	var panel := _days(results, 80)
	var n := panel.model.infra_declined_count()
	assert_int(n).is_greater(0)
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.decline.cause", {"cause": UiText.t(&"m2.decline.infrastructure")}))
	var hint_key := &"m2.hint.infrastructure" if n == 1 else &"m2.hint.infrastructure_n"
	assert_str(text).contains(UiText.t(hint_key, {"n": n}))
	assert_str(text).contains("yol eklemek")


func test_hint_is_absent_when_no_parcel_was_declined_for_infrastructure() -> void:
	var results := _open(_facade())
	var panel := results.results_panel()  # öneri anı: henüz karar yok
	assert_int(panel.model.infra_declined_count()).is_equal(0)
	assert_str(panel.joined_text()).not_contains("yol eklemek")


func test_hint_count_falls_when_a_road_adds_capacity() -> void:
	var results := _open(_facade())
	var before := _days(results, 60).model.infra_declined_count()
	assert_bool(E.road_a(results.facade as SimFacadeImpl).is_rejected()).is_false()
	var after := _days(results, 80).model.infra_declined_count()
	assert_int(before).is_greater(0)
	assert_int(after).override_failure_message("yol sonrası bazı parseller yatırım almalı: %d -> %d" % [before, after]) \
		.is_less(before)


# --- bildirim şeridi ---

func _strip() -> NotificationStrip:
	var s := NotificationStrip.create(UiContext.for_profile_name(&"desktop"))
	add_child(s)
	return auto_free(s)


func _decline(seq: int, parcel: int, code: String) -> SimEvent:
	var e := SimEvent.new()
	e.seq = seq
	e.kind = &"actor.decided"
	e.message_key = &"event.investor.declined"
	e.args = {"code": code}
	e.subjects = PackedStringArray(["parcel.%d" % parcel])
	return e


func test_strip_folds_infrastructure_declines_into_one_actionable_line() -> void:
	var s := _strip()
	var evs: Array[SimEvent] = []
	for k in 4:
		evs.append(_decline(k + 1, 10 + k, "infrastructure_exhausted"))
	evs.append(_decline(5, 10, "infrastructure_exhausted"))  # aynı parsel: sayıya eklenmez
	s.push_events(evs)
	assert_int(s.row_count()).is_equal(0)
	assert_int(s.infra_count()).is_equal(4)
	assert_str(s.infra_summary_text()).is_equal(UiText.t(&"strip.infra_summary", {"n": 4}))
	assert_str(s.infra_summary_text()).contains("yol eklemek")
	assert_bool(s.visible).is_true()


func test_strip_infra_count_drops_when_parcel_gets_investment_and_other_declines_stay_listed() -> void:
	var s := _strip()
	s.push_events([_decline(1, 10, "infrastructure_exhausted"), _decline(2, 11, "infrastructure_exhausted"),
			_decline(3, 12, "demand_too_low")])
	assert_int(s.infra_count()).is_equal(2)
	assert_int(s.row_count()).override_failure_message("talep reddi tek satır olarak kalır").is_equal(1)
	var ok := SimEvent.new()
	ok.seq = 4
	ok.kind = &"actor.decided"
	ok.message_key = &"event.investor.develop"
	ok.subjects = PackedStringArray(["parcel.10"])
	s.push_events([ok])
	assert_int(s.infra_count()).is_equal(1)
	s.clear()
	assert_int(s.infra_count()).is_equal(0)
	assert_str(s.infra_summary_text()).is_empty()
