extends SimTestBase
## T-049 (tick maliyeti) · Aylık arsa değeri güncellemesi plansız modda yalnız görülen imarı olan (`zone_seen`)
## parsellere bakar; sonuç TAM taramayla bit-bit aynıdır. Eski (tam tarama) koddan alınan durum hash'i sabittir;
## ayrıca davranış: plansız boş parselin değeri DEĞİŞMEZ, planlı boş parselin değeri talep varken artar
## (spekülasyon), bayrak kapalıyken (tam tarama) placeholder imarlı parseller de artar.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
## Yatırım kapalı (altyapı kapasitesi 1: imar sonrası dikkat değerlendirmesi de kapasite vetosuyla bina çıkarmaz):
## değerler yalnız aylık akıştan gelir. Aşırı talep: 5000 hane.
const BASE := {
	"decision": {"review_enabled": 0},
	"regions": {"defaults": {"initial_households": 5000, "infra_capacity_units": 1}},
	"investors": {"list": [
		{"capital": 80000, "threshold_shift": 0, "monthly_inflow": 0},
		{"capital": 80000, "threshold_shift": 0, "monthly_inflow": 0},
	]},
}
## Eski kodla (tam tarama) üretilmiş: plansız mod, 2 planlı parsel, 95 gün.
const OLD_CODE_STATE_HASH := "aa8b3b2c3dc5b88f045fbf3922466c1c0527b6b8846ee0a7064ad37246fdaead"


func _land(f: SimFacadeImpl, p: int) -> int:
	return EconomyQuery.parcel_record(f.game_state(), p)["land_value"]


func _unplanned_run() -> SimFacadeImpl:
	var h := W.handle(S.merge(BASE, {"decision": {"unplanned_land_enabled": 1}}))
	var f: SimFacadeImpl = h.facade
	var ids := f.parcel_ids()
	assert_bool(f.submit_command(SimCommand.zoning_propose(PackedInt64Array([ids[0], ids[1]]),
			&"zone.residential")).is_rejected()).is_false()
	f.advance(95)
	return f


func test_unplanned_mode_changes_only_planned_vacant_land() -> void:
	var f := _unplanned_run()
	var ids := f.parcel_ids()
	assert_int(_land(f, int(ids[0]))).override_failure_message("planlı boş parsel spekülasyonla artmalı").is_greater(1000)
	assert_int(_land(f, int(ids[1]))).is_equal(_land(f, int(ids[0])))
	for k in range(2, ids.size()):
		assert_int(_land(f, int(ids[k]))).override_failure_message("plansız parsel %d değişmemeli" % k).is_equal(1000)


func test_unplanned_mode_state_hash_equals_the_full_scan_value() -> void:
	assert_str(_unplanned_run().state_hash()).is_equal(OLD_CODE_STATE_HASH)


func test_flag_off_still_bids_up_every_buildable_placeholder_parcel() -> void:
	var f := W.facade(BASE)
	f.advance(95)
	for p in f.parcel_ids():
		assert_int(_land(f, int(p))).override_failure_message("bayrak kapalı: placeholder imarlı parsel artmalı") \
			.is_greater(1000)
