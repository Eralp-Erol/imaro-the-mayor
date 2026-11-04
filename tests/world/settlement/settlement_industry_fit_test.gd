extends GdUnitTestSuite
## T-062 A2-düzeltme · sanayi hero'su (ind_hero 22 x 39,5 m) yerleşimi: iş yeri sayısı
## (WLD-04/08, SIM-01, CAN-03, TEK-01/02).
## Kök neden: hero ayak izinin derinliği (39,5 m) çekirdek/kompakt lot derinliğini (D1/D6 medyan 32 m, p90 37 m)
## aşar; dik
## yerleşim neredeyse hiç sığmaz (A2: D1/D6/D5 iş yeri 0/0/2; kit 115/135/21). Düzeltme: `family_roles.rotate_fit` ile
## birleşik cephe zincirinde yaw + 90 derece (uzun kenar sokağa paralel), RNG tüketimi olmayan deterministik fallback.
## Her kural olumsuz varyantla kanıtlanır (rotate_fit kapalı kontrol verisi, bozulmuş yönelim).

## Kit düzeyi (A2 öncesi ölçüm) ve en az yarısı: D1 115, D6 135, D5 21. Ölçülen (test tohumu): 103 / 134 / 17.
const KIT_LEVEL := {&"D1": 115, &"D6": 135, &"D5": 21}
const ORIENT_MAX_DEG := 25.0
const IND_FAMILY := "hero_ind_hero"


## Yapının cephe yüzü (modül +Z) cephe yolu doğrultusuna paralel mi: yaw + 90 derece dönmüş yerleşim.
static func is_rotated(res: SettlementResult, i: int) -> bool:
	var net := res.net
	var p := net.parcel(res.columns.parcel_id[i])
	if p == null or not net.edges.has(p.frontage_edge):
		return false
	var e: WorldRoadEdge = net.edges[p.frontage_edge]
	var road_dir := (net.node_pos(e.b) - net.node_pos(e.a)).normalized()
	var face := Vector2(sin(res.columns.yaw[i]), cos(res.columns.yaw[i]))
	return absf(face.dot(road_dir)) >= cos(deg_to_rad(ORIENT_MAX_DEG))


static func workplaces(res: SettlementResult, code: StringName) -> int:
	return int(SettlementStats.region_mix(res, code)["workplaces"])


static func _cloned_with_yaw(src: SettlementResult, index: int, new_yaw: float) -> SettlementResult:
	var cols := BuildingColumns.new()
	var s := src.columns
	for i in s.count:
		cols.add(s.parcel_id[i], s.module_idx[i], s.x[i], s.z[i], new_yaw if i == index else s.yaw[i], s.floors[i],
				s.wall_row[i], s.roof_row[i], s.accent_row[i], s.bright[i], s.flags[i], s.era[i])
	return SettlementResult.with_columns(src, cols)


# --- kök neden (veri) ---

func test_root_cause_the_ind_hero_depth_exceeds_core_lot_depth_but_its_width_fits() -> void:
	var rules := SettlementTestSupport.rules()
	var seen := 0
	for m in rules.modules:
		if m.family != IND_FAMILY:
			continue
		seen += 1
		assert_float(m.d).override_failure_message("%s derinlik" % m.id).is_greater(39.0)
		assert_float(m.w).override_failure_message("%s genişlik" % m.id).is_less(23.0)
		assert_bool(m.rotate_fit).override_failure_message("%s rotate_fit" % m.id).is_true()
		assert_bool(m.floors_working_value).is_true()   # kat uydurulmadı: bilinmeyen -> çalışma değeri 1
		assert_int(m.floors).is_equal(1)
	assert_int(seen).is_equal(3)
	for m in rules.modules:
		if m.family != IND_FAMILY:
			assert_bool(m.rotate_fit).override_failure_message("%s döndürülemez olmalı" % m.id).is_false()


func test_only_the_industry_family_may_rotate_and_the_shop_role_stays_with_the_bazaar() -> void:
	var roles: Dictionary = SettlementTestSupport.control()["family_roles"]
	for fam: String in roles:
		assert_bool(bool((roles[fam] as Dictionary).get("rotate_fit", false))).override_failure_message(fam) \
				.is_equal(fam == IND_FAMILY)
		assert_bool(bool((roles[fam] as Dictionary).get("ground_shop", false))).override_failure_message(fam) \
				.is_equal(fam == "hero_com_bazaar")


# --- iş yeri sayısı (tam Ismeral) ---

func test_d1_d6_d5_have_workplaces_at_least_half_the_kit_level() -> void:
	var res := SettlementTestSupport.full()
	for code: StringName in KIT_LEVEL:
		var want: int = int(KIT_LEVEL[code]) / 2
		assert_int(workplaces(res, code)).override_failure_message("%s işyeri (kit %d)" % [code, KIT_LEVEL[code]]) \
				.is_greater(want)


func test_rotated_ind_hero_sits_along_the_street_inside_the_parcels_without_overlap() -> void:
	var res := SettlementTestSupport.full()
	var rotated := 0
	var upright := 0
	for i in res.columns.count:
		if (res.columns.flags[i] & BuildingColumns.FLAG_INDUSTRY) == 0:
			continue
		var m := res.module_of(i)
		assert_str(m.family).is_equal(IND_FAMILY)   # sanayi bayrağı yalnız ind_hero; başka aile işyeri olarak kullanılmaz
		if is_rotated(res, i):
			rotated += 1
		else:
			upright += 1
	assert_int(rotated).override_failure_message("döndürülmüş sanayi yapısı").is_greater(200)
	assert_int(int(res.stats["wide_rotated"])).is_greater(200)
	assert_int(upright).override_failure_message("dik sanayi (avlu/tarla)").is_greater(0)
	# Bina-bina ve parsel (yol) dışı çakışma yok: döndürülmüş ayak izi dahil bütün yapı.
	assert_array(SettlementInvariants.check_in_parcels(res)).is_empty()
	assert_array(SettlementInvariants.check_no_overlap(res)).is_empty()
	assert_array(SettlementInvariants.check_on_land(res)).is_empty()
	assert_array(SettlementInvariants.check_orientation(res)).is_empty()
	assert_array(SettlementInvariants.check_islands(res)).is_empty()


func test_only_approved_hero_identities_are_used_by_the_rotated_industry() -> void:
	var res := SettlementTestSupport.full()
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	var ids := {}
	for i in res.columns.count:
		if is_rotated(res, i) and (res.columns.flags[i] & BuildingColumns.FLAG_INDUSTRY) != 0:
			ids[res.module_of(i).id] = true
	assert_int(ids.size()).is_greater(0)
	for id: String in ids:
		assert_bool(gate.is_approved(id)).override_failure_message(id).is_true()
		assert_str(id).starts_with("bld_hero_ind_hero_")


# --- olumsuz: döndürme kapalıysa iş yeri çökmesi geri gelir ---

func test_negative_without_rotate_fit_the_core_regions_lose_their_workplaces() -> void:
	var c := SettlementTestSupport.control()
	(c["family_roles"][IND_FAMILY] as Dictionary)["rotate_fit"] = false
	var off := SettlementTestSupport.light_with(SettlementTestSupport.SEED, c)
	var on := SettlementTestSupport.light()
	assert_int(int(off.stats["wide_rotated"])).is_equal(0)
	assert_int(int(on.stats["wide_rotated"])).is_greater(20)
	for code in [&"D1", &"D6"]:
		assert_int(workplaces(off, code)).override_failure_message("%s rotate_fit kapalı" % code).is_less(5)
		assert_int(workplaces(on, code)).override_failure_message("%s rotate_fit açık" % code).is_greater(15)


func test_negative_a_non_rotatable_family_is_never_rotated() -> void:
	var res := SettlementTestSupport.full()
	for i in res.columns.count:
		if not res.module_of(i).rotate_fit:
			assert_bool(res.module_of(i).family != IND_FAMILY).is_true()
	# Dik yönelim zorunlu aileler: döndürülmüş (cephe yola paralel) yapı yok.
	var wrong := 0
	for i in res.columns.count:
		var m := res.module_of(i)
		if not m.rotate_fit and (res.columns.flags[i] & BuildingColumns.FLAG_LANDMARK) == 0 and is_rotated(res, i):
			wrong += 1
	assert_int(wrong).is_equal(0)


func test_negative_the_orientation_invariant_still_rejects_a_misrotated_building() -> void:
	var res := SettlementTestSupport.light()
	var plain := -1
	var ind_rot := -1
	for i in res.columns.count:
		if plain < 0 and not res.module_of(i).rotate_fit and res.columns.flags[i] == 0:
			plain = i
		if ind_rot < 0 and res.module_of(i).rotate_fit and is_rotated(res, i):
			ind_rot = i
	assert_int(plain).is_greater(-1)
	assert_int(ind_rot).is_greater(-1)
	assert_array(SettlementInvariants.check_orientation(res)).is_empty()
	# Döndürülemez aile 90 derece dönerse ihlal; döndürülebilir ailede 45 derece (ne dik ne yan) ihlal.
	var bad_plain := _cloned_with_yaw(res, plain, res.columns.yaw[plain] + PI * 0.5)
	assert_array(SettlementInvariants.check_orientation(bad_plain)).is_not_empty()
	var bad_ind := _cloned_with_yaw(res, ind_rot, res.columns.yaw[ind_rot] + PI * 0.25)
	assert_array(SettlementInvariants.check_orientation(bad_ind)).is_not_empty()
	# Döndürülebilir ailede ters yan (yaw + 180 derece; yüz yine yol boyunca) geçerli yan yönelimdir.
	var flipped := _cloned_with_yaw(res, ind_rot, res.columns.yaw[ind_rot] + PI)
	assert_array(SettlementInvariants.check_orientation(flipped)).is_empty()


# --- determinizm ---

func test_same_seed_is_byte_equal_with_rotation_and_a_different_seed_differs() -> void:
	var a := SettlementTestSupport.light()
	var b := SettlementTestSupport.light_with(SettlementTestSupport.SEED, SettlementTestSupport.control())
	assert_int(int(a.stats["wide_rotated"])).is_greater(20)
	assert_str(a.columns.state_hash()).is_equal(b.columns.state_hash())
	assert_array(Array(a.columns.yaw)).is_equal(Array(b.columns.yaw))
	var other := SettlementTestSupport.light_with(SettlementTestSupport.SEED + 1, SettlementTestSupport.control())
	assert_str(other.columns.state_hash()).is_not_equal(a.columns.state_hash())
	assert_str(other.topology_hash()).is_equal(a.topology_hash())   # doluluk kurası tohumdan bağımsız
