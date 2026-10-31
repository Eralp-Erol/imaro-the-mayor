extends SimTestBase
## T-043B ek · Görünüm katmanı tutarlılığı: `unplanned_land_enabled` iken plansız boş parselde `ParcelView.zone` boştur
## (`plan_state` ile aynı kural), ekonomi durumu kurulmadan önce (tick 0) de. Bayrak kapalıyken şablon imarı değişmez.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ENABLED := {"decision": {"unplanned_land_enabled": 1}}


func _favorable() -> Dictionary:
	return S.merge(ENABLED, S.regions({"F1": S.favorable(), "F2": S.favorable()}))


func test_unplanned_vacant_parcel_view_has_no_zone_even_before_the_first_tick() -> void:
	# T-043B ek: ekonomi durumu ilk günlük tick'te kurulur; ondan ÖNCE de sözleşme boş imar bekler (plan_state
	# `unplanned` der, görünüm şablon placeholder'ını `zone.residential` göstermemeli).
	var h := W.handle(_favorable())
	var f := h.facade
	for p in f.parcel_ids():
		assert_str(String(h.system.plan_state(f.game_state(), int(p))["state"])).is_equal("unplanned")
		assert_str(String(f.parcel_views(PackedInt64Array([p]))[0].zone)) \
			.override_failure_message("tick 0'da plansız parselde placeholder imar göründü (%d)" % p).is_equal("")
	# Teklif verilmiş (bekleyen) parsel de tick 0 sonrası aynı kuralı izler; yürürlükteki imar yoktur.
	var q := int(f.parcel_ids(S.R1)[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([q]), &"zone.mixed"))
	f.advance(1)
	var v := f.parcel_views(PackedInt64Array([q]))[0]
	assert_str(String(v.zone)).is_equal("")
	assert_str(String(v.pending_zone)).is_equal("zone.mixed")


func test_view_zone_keeps_the_template_zone_when_the_flag_is_off_even_before_the_first_tick() -> void:
	var f := W.facade(S.regions({"F1": S.favorable()}))
	assert_str(String(f.parcel_views(f.parcel_ids())[0].zone)).is_equal("zone.residential")


func test_t0_built_parcel_keeps_its_zone_at_tick_zero_and_a_planned_parcel_shows_the_plan_zone() -> void:
	var stock := ListStockSource.create([{"parcel_id": 1, "use": "residential", "units": 8, "owner": 0}])
	var h := W.handle(_favorable(), S.SEED, S.PER_REGION, stock)
	var f := h.facade
	assert_str(String(f.parcel_views(PackedInt64Array([1]))[0].zone)) \
		.override_failure_message("yapılı parselin imarı gizlendi") \
		.is_equal("zone.residential")
	assert_str(String(f.parcel_views(PackedInt64Array([2]))[0].zone)).is_equal("")  # aynı dünyada boş komşu plansız
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
	f.advance(5)  # komut + apply_delay_days: plan yürürlükte
	assert_str(String(f.parcel_views(PackedInt64Array([2]))[0].zone)).is_equal("zone.commercial")
