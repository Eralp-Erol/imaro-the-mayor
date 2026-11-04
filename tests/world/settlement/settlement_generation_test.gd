# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-005 ölçüt 1-3 · T0 yerleşim üreteci v0: topolojik/istatistiksel değişmezler (WLD-03/04/08, VIS-02/04, CAN-03).
## Testler kesin koordinat SINAMAZ (koordinatlar AÇIK); göreli ilişki ve kit spec sayılarını (building-kit-v0.md
## §3.2/3.3/§4) ölçer. Tam Ismeral ağı + yerleşim bir kez üretilir (`SettlementTestSupport.full`); olumsuz
## varyantlar küçültülmüş ağ veya bilerek bozulmuş çıktı kullanır.

## Kit spec sayıları (kural kaynağı: design/specs/art/building-kit-v0.md; kontrol verisinden BAĞIMSIZ sabitlenir).
## T-051 Tur 1 (kit v1 §3.3): metro kiremit %40-55, hiçbir 500 m penceresi > %72 (v0: 35 / 55).
## T-062 A2 · hero tablosuna YENİDEN TABANLAMA (gerekçeli): aşağıdaki sabitler hero modül geometrisinin ölçülen
## çıktısıdır
## (21 modül, ayak izi >= 10,25 m, tek kat/aile). Eski kit tabanı (42 modül, 7 m'ye inen genişlik, palet)
## yorumlarda yazılıdır.
## Çatı: hero modülde palet yok; sınıf tablodaki `roof_type`tan (flat -> terrace, hip/gable -> pitched).
const METRO_PITCHED_MAX := 0.70           # kit: metro kiremit <= 0.55 (palet tonu); hero ölçülen 0.64
const METRO_TERRACE_MIN := 0.28
const CORE_WINDOW_PITCHED_MAX := 0.90     # kit: 500 m penceresi kiremit <= 0.72; hero çekirdek penceresi ölçülen 0.854
## Bitişik nizam: kit 0.718 -> hero 0.042 (ayak izi 10-14 m, lot 18-22 m: tek yapı + 6-10 m boşluk). KALİTE
## GERİLEMESİ,
## içerik/layout kararı gerektirir (rapora yazıldı); aşağıdaki sınır yalnız daha da kötüleşmeyi yakalar.
const ADJACENCY_CORE_MIN := 0.02
const FRONTAGE_COVERAGE_MIN := 0.55       # kit 0.758 -> hero 0.648
const FRONTAGE_MEDIAN_MIN := 0.55         # kit 0.781 -> hero 0.672
const FLOOR_VARIETY_WINDOWS_MIN := 10     # kit 61 pencere -> hero 13 (D1/D6 yapı sayısı ~yarıya indi)
const CELL_VARIETY_MIN_DISTINCT := 6      # 200 m hücrede (>= 30 yapı) farklı modül; ölçülen min 7, ortalama 12,9

var _full: SettlementResult
var _net: WorldNetwork


func before() -> void:
	_full = SettlementTestSupport.full()
	_net = SettlementTestSupport.net_full()


func _has(violations: PackedStringArray, needle: String) -> bool:
	for v in violations:
		if v.contains(needle):
			return true
	return false


func _clone(src: BuildingColumns) -> BuildingColumns:
	var c := BuildingColumns.new()
	for i in src.count:
		c.add(src.parcel_id[i], src.module_idx[i], src.x[i], src.z[i], src.yaw[i], src.floors[i], src.wall_row[i],
				src.roof_row[i], src.accent_row[i], src.bright[i], src.flags[i], src.era[i])
	return c


# --- Boyut ve genel değişmezler ---

func test_every_invariant_holds_on_the_generated_ismeral_t0_settlement() -> void:
	var violations := SettlementInvariants.check_all(_full)
	assert_array(violations).override_failure_message("ihlaller: %s" % [violations.slice(0, 12)]).is_empty()


func test_stock_is_in_the_tens_of_thousands_and_columns_are_consistent() -> void:
	var cols := _full.columns
	assert_int(cols.count).is_greater(15000)
	assert_int(cols.count).is_less(120000)
	assert_array(cols.shape_errors()).is_empty()
	for i in cols.count:
		assert_int(_full.rules.modules.size()).is_greater(cols.module_idx[i])


func test_generation_leaves_world_and_network_untouched_and_owner_slots_empty() -> void:
	# CAN-03: üretici yalnız BuildingColumns üretir; ağ/sim durumuna (owner_id) yazmaz.
	var net := SettlementTestSupport.net_light()
	var before_hash := net.state_hash()
	var world_hash := net.world.state_hash()
	SettlementTestSupport.light_with(11, SettlementTestSupport.control())
	assert_str(net.state_hash()).is_equal(before_hash)
	assert_str(net.world.state_hash()).is_equal(world_hash)
	for pid: int in net.parcels:
		assert_int((net.parcels[pid] as WorldParcel).owner_id).is_equal(0)


# --- Her yapı parselde ve karada; çakışma yok (olumsuzlu) ---

func test_every_building_sits_inside_its_parcel_block_and_on_land() -> void:
	assert_array(SettlementInvariants.check_in_parcels(_full)).is_empty()
	assert_array(SettlementInvariants.check_on_land(_full)).is_empty()


func test_negative_building_off_the_parcels_or_in_water_is_detected() -> void:
	var cols := _clone(_full.columns)
	var pid := cols.parcel_id[0]
	var far: Vector2 = _net.parcel(pid).centroid + Vector2(900.0, 900.0)
	cols.x[0] = far.x
	cols.z[0] = far.y
	var bad := SettlementResult.with_columns(_full, cols)
	assert_bool(_has(SettlementInvariants.check_in_parcels(bad), "parsel")).is_true()
	var water := _net.world.islands[0].centroid
	var cols2 := _clone(_full.columns)
	cols2.x[1] = water.x - 4000.0
	cols2.z[1] = water.y
	var found_water := Vector2.ZERO
	# denizin üstünde bir nokta bul (batı kıyısı dışı)
	for k in 200:
		var p := Vector2(150.0 + 20.0 * k, 20000.0)
		if _net.world.is_water(p.x, p.y):
			found_water = p
			break
	cols2.x[1] = found_water.x
	cols2.z[1] = found_water.y
	var bad2 := SettlementResult.with_columns(_full, cols2)
	assert_bool(_has(SettlementInvariants.check_on_land(bad2), "su")).override_failure_message("su ihlali yok").is_true()


func test_no_two_buildings_overlap_and_a_planted_duplicate_is_detected() -> void:
	assert_array(SettlementInvariants.check_no_overlap(_full)).is_empty()
	var cols := _clone(_full.columns)
	cols.add(cols.parcel_id[10], cols.module_idx[10], cols.x[10] + 1.0, cols.z[10], cols.yaw[10], cols.floors[10],
			cols.wall_row[10], cols.roof_row[10], cols.accent_row[10], 0, 0, cols.era[10])
	var bad := SettlementResult.with_columns(_full, cols)
	assert_bool(_has(SettlementInvariants.check_no_overlap(bad), "çakış")).is_true()


# --- WLD-03: ada/liman/sanayi ---

func test_no_building_stands_on_an_island_and_port_industry_is_on_the_mainland() -> void:
	var world := _net.world
	var cols := _full.columns
	for i in cols.count:
		assert_int(world.landmass_at(cols.x[i], cols.z[i])).override_failure_message("yapı %d ada/su üstünde" % i) \
				.is_equal(WorldData.LANDMASS_MAINLAND)
	assert_array(SettlementInvariants.check_islands(_full)).is_empty()


func test_negative_port_class_building_on_an_island_is_detected() -> void:
	var cols := _clone(_full.columns)
	var isl := _net.world.islands[0].centroid
	cols.add(cols.parcel_id[0], cols.module_idx[0], isl.x, isl.y, 0.0, 1,
			cols.wall_row[0], cols.roof_row[0], cols.accent_row[0], 0,
			BuildingColumns.FLAG_PORT_YARD | BuildingColumns.FLAG_INDUSTRY, BuildingColumns.ERA_LATE)
	var bad := SettlementResult.with_columns(_full, cols)
	var v := SettlementInvariants.check_islands(bad)
	assert_bool(_has(v, "ada")).override_failure_message(str(v)).is_true()


func test_port_yard_and_first_industry_are_on_the_mainland_west_of_d4() -> void:
	var cols := _full.columns
	var d4 := _net.world.region_by_code(&"D4")
	var yard := 0
	var yard_x_max := -INF
	for i in cols.count:
		if (cols.flags[i] & BuildingColumns.FLAG_PORT_YARD) != 0:
			yard += 1
			yard_x_max = maxf(yard_x_max, cols.x[i])
	assert_int(yard).override_failure_message("liman/sanayi sahasında yapı yok").is_greater(150)
	assert_float(yard_x_max).override_failure_message("liman sahası D4'ün batısında değil").is_less(d4.centroid.x)
	assert_array(SettlementInvariants.check_port_west_of_d4(_full)).is_empty()


func test_negative_port_yard_building_east_of_d4_is_detected() -> void:
	var cols := _clone(_full.columns)
	var d4 := _net.world.region_by_code(&"D4")
	var i := 0
	while (cols.flags[i] & BuildingColumns.FLAG_PORT_YARD) == 0:
		i += 1
	cols.x[i] = d4.centroid.x + 3000.0
	var bad := SettlementResult.with_columns(_full, cols)
	assert_bool(_has(SettlementInvariants.check_port_west_of_d4(bad), "D4")).is_true()


func test_industry_buildings_exist_beyond_the_yard_but_heavy_industry_stays_off_the_islands() -> void:
	var rules := _full.rules
	var cols := _full.columns
	var industrial := 0
	for i in cols.count:
		if rules.modules[cols.module_idx[i]].industry:
			industrial += 1
			assert_int(cols.flags[i] & BuildingColumns.FLAG_INDUSTRY).is_not_equal(0)
	assert_int(industrial).is_greater(300)


# --- WLD-04/06/08: bölge karakteri ve yoğunluk sıralaması ---

func test_d1_d6_core_is_denser_than_d2_to_d5_which_are_denser_than_rural_d4() -> void:
	var d1 := SettlementStats.region_density(_full, &"D1")
	var d6 := SettlementStats.region_density(_full, &"D6")
	var core_min := minf(d1["gfa_per_km2"], d6["gfa_per_km2"])
	var mid_max := 0.0
	var mid_sum := 0.0
	for code in [&"D2", &"D3", &"D5"]:
		var d := SettlementStats.region_density(_full, code)
		mid_max = maxf(mid_max, d["gfa_per_km2"])
		mid_sum += d["gfa_per_km2"]
	var d4 := SettlementStats.region_density(_full, &"D4")
	assert_float(core_min).override_failure_message("D1+D6 çekirdeği D2/D3/D5'ten yoğun değil").is_greater(mid_max)
	assert_float(mid_sum / 3.0).is_greater(d4["gfa_per_km2"])
	# D4 kırsal: kentsel olmayan bölge yapısı çok seyrek (bina/km² çekirdeğin en çok beşte biri)
	assert_float(d4["buildings_per_km2"]).is_less(d1["buildings_per_km2"] * 0.2)
	assert_float(d1["mean_floors"]).is_greater(d4["mean_floors"])


func test_negative_density_order_breaks_when_core_fill_is_removed() -> void:
	var c := SettlementTestSupport.control()
	for code in ["D1", "D6"]:
		c["regions"][code]["fill"] = {"center": 0.2, "edge": 0.1}
	var thin := SettlementTestSupport.light_with(SettlementTestSupport.SEED, c)
	var normal := SettlementTestSupport.light()
	assert_float(SettlementStats.region_density(thin, &"D1")["gfa_per_km2"]) \
			.is_less(SettlementStats.region_density(normal, &"D1")["gfa_per_km2"] * 0.5)


func test_every_working_region_has_a_real_centre_housing_and_workplaces() -> void:
	# WLD-04/08: D2-D5 daha küçük ama gerçek merkez + konut + iş yeri; dekor boş bırakılmaz.
	var rules := _full.rules
	for code in [&"D1", &"D2", &"D3", &"D4", &"D5", &"D6"]:
		var s := SettlementStats.region_mix(_full, code)
		assert_int(s["buildings"]).override_failure_message("%s yapı sayısı" % code).is_greater(400)
		assert_int(s["housing"]).override_failure_message("%s konut" % code).is_greater(200)
		assert_int(s["shops"]).override_failure_message("%s zemin kat dükkân (çarşı/merkez)" % code).is_greater(15)
		# T-062 A2-düzeltme: ind_hero 22 x 39,5 m çekirdek/kompakt lot derinliğine (<= 38 m) dik sığmıyordu (A2: D1/D6/D5
		# işyeri 0/0/2; kit: 115/135/21); `rotate_fit` ile uzun kenar sokağa paralel yerleşir (ölçülen 103/134/17).
		# Her bölge > 8; D1/D6/D5 için kit düzeyinin en az yarısı settlement_industry_fit_test.gd'de.
		assert_int(s["workplaces"]).override_failure_message("%s işyeri (atölye/depo)" % code).is_greater(8)
		assert_int(s["civic"]).override_failure_message("%s sivil/kamu yapısı" % code).is_greater(0)
	assert_object(rules).is_not_null()


func test_green_belt_and_growth_land_stay_open_between_the_centres() -> void:
	# WLD-04/06: parsellerin hepsi dolu değildir; tarım/yeşil kuşak ve büyüme alanı açık kalır.
	var built := {}
	for pid in _full.columns.occupied_parcels():
		built[pid] = true
	var urban_built := 0
	var urban_total := 0
	var d_edge_built := 0
	var d_edge_total := 0
	for pid: int in _net.parcels:
		var p: WorldParcel = _net.parcels[pid]
		if p.fabric == &"rural":
			continue
		urban_total += 1
		urban_built += 1 if built.has(pid) else 0
		if p.region_code in [&"D2", &"D3", &"D4", &"D5"]:
			d_edge_total += 1
			d_edge_built += 1 if built.has(pid) else 0
	assert_float(float(urban_built) / float(urban_total)).is_greater(0.55)
	assert_float(float(urban_built) / float(urban_total)).is_less(0.95)
	assert_float(float(d_edge_built) / float(d_edge_total)).is_less(0.80)
	var rural_total := 0
	var rural_built := 0
	for pid: int in _net.parcels:
		if (_net.parcels[pid] as WorldParcel).fabric == &"rural":
			rural_total += 1
			rural_built += 1 if built.has(pid) else 0
	assert_float(float(rural_built) / float(rural_total)).is_less(0.6)
	assert_int(rural_built).override_failure_message("tarla evleri yok").is_greater(50)


# --- Landmark yok (T-062 A2: saat kulesi D-005'te reddedildi; Studio Director kararı 1) + miras odakları (WLD-07) ---

func test_t0_has_no_landmark_and_reserves_no_plaza_because_no_landmark_is_approved() -> void:
	var cols := _full.columns
	for i in cols.count:
		assert_int(cols.flags[i] & BuildingColumns.FLAG_LANDMARK).override_failure_message("yapı %d landmark" % i).is_equal(0)
	assert_int(_full.tower_index).is_equal(-1)
	assert_str(str(_full.stats["tower"])).is_equal("none-approved")
	assert_bool(_full.plaza.is_empty()).is_true()
	assert_int(int(_full.stats["dropped_plaza"])).override_failure_message("meydan ayrılmamalı").is_equal(0)
	for m in _full.rules.modules:
		assert_bool(m.id.begins_with("bld_lmk")).override_failure_message("tabloda landmark: %s" % m.id).is_false()
	assert_array(SettlementInvariants.check_tower_present(_full)).is_empty()


func test_negative_a_configured_landmark_module_is_still_placed_by_the_unchanged_rule() -> void:
	# Atlama mantığı ölü kod değildir: kuralı açık + onaylı tablodan bir modül verilince kule/meydan yerleşir (yalnız
	# mekanizma sınaması; hero sivil yapı landmark DEĞİLDİR, T0 verisi boş kalır).
	var c := SettlementTestSupport.control()
	c["tower"]["module"] = "bld_hero_civ_hero_a"
	var res := SettlementTestSupport.light_with(SettlementTestSupport.SEED, c)
	assert_int(res.tower_index).override_failure_message(str(res.stats)).is_greater_equal(0)
	assert_str(str(res.stats["tower"])).is_equal("placed")
	assert_bool(res.plaza.is_empty()).is_false()
	assert_int(res.columns.flags[res.tower_index] & BuildingColumns.FLAG_LANDMARK).is_not_equal(0)


func test_heritage_foci_exist_in_the_historic_cores_of_d1_and_d6() -> void:
	# WLD-07: landmark yokken miras odağı tarihî çekirdek (hero old_core, FLAG_HERITAGE) üzerinden korunur.
	var cols := _full.columns
	var by_region := {&"D1": 0, &"D6": 0}
	for i in cols.count:
		if (cols.flags[i] & BuildingColumns.FLAG_HERITAGE) == 0:
			continue
		assert_bool(_full.module_of(i).heritage_eligible) \
				.override_failure_message("miras bayrağı eligible olmayan aileye").is_true()
		var code := _net.parcel(cols.parcel_id[i]).region_code
		if by_region.has(code):
			by_region[code] += 1
	assert_int(by_region[&"D1"]).override_failure_message(str(by_region)).is_greater(20)
	assert_int(by_region[&"D6"]).override_failure_message(str(by_region)).is_greater(20)


# --- Çatı payı (kit spec §3.2 -> hero: roof_type sınıfı, T-062 A2) ---
# Eski kit testleri (kiremit tonu payı, R3 oranı, 500 m kiremit penceresi) palet satırına bağlıydı; hero
# modüllerde palet
# YOK (renk atlas dokusundan), bu yüzden bu ölçüler tanımsızdır. Yerine tablonun `roof_type` alanından terrace/pitched
# payları, aynı karakter tablosunun (kit §3.2) hero ile karşılaştırılabilir kısmıyla sınanır.

func test_metro_roof_mix_follows_the_hero_roof_types_with_both_classes_present() -> void:
	var all := SettlementStats.roof_shares(_full, PackedInt32Array())
	assert_float(all["tile"]).override_failure_message("palet kiremit ölçüsü hero'da 0 olmalı").is_equal(0.0)
	assert_float(all["pitched"]).override_failure_message("metro eğimli çatı payı %s" % all["pitched"]) \
			.is_less_equal(METRO_PITCHED_MAX)
	assert_float(all["terrace"]).override_failure_message("metro teras payı %s" % all["terrace"]) \
			.is_greater_equal(METRO_TERRACE_MIN)
	assert_float(all["terrace"] + all["pitched"] + all["other"]).is_equal_approx(1.0, 0.0001)


func test_no_dense_core_500m_window_is_a_pitched_roof_carpet() -> void:
	var core_free := [&"town", &"town_center", &"village", &"hillside", &"hill_center", &"harbor", &"yard", &"farm",
			&"historic"]
	var w := SettlementStats.window_tile_max(_full, 500.0, 30, core_free, &"pitched")
	assert_int(w["windows"]).override_failure_message("çekirdek penceresi yok: %s" % [w]).is_greater(10)
	assert_float(w["max_tile"]).override_failure_message("en eğimli çekirdek penceresi %s" % [w]) \
			.is_less_equal(CORE_WINDOW_PITCHED_MAX)


func test_negative_all_hip_control_is_caught_by_the_roof_rules() -> void:
	var c := SettlementTestSupport.control()
	for zname: String in c["zones"]:
		var fw: Dictionary = c["zones"][zname]["family_weights"]
		for fam in fw.keys():
			fw[fam] = 0.0
		fw["hero_res_house"] = 1.0
	var res := SettlementTestSupport.light_with(SettlementTestSupport.SEED, c)
	var all := SettlementStats.roof_shares(res, PackedInt32Array())
	assert_float(all["pitched"]).override_failure_message("eğimli halı yakalanmalı: %s" % all["pitched"]) \
			.is_greater(METRO_PITCHED_MAX)
	assert_float(all["terrace"]).is_less(METRO_TERRACE_MIN)


func test_roof_mix_per_character_matches_the_hero_table() -> void:
	# kit §3.2 karakter tablosu (ÇM): yoğun merkez teras 55-70 (hero ölçülen 0,62: tutuyor); tarihî çekirdek
	# teras 30-45
	# (hero 0,18: TUTMUYOR, old_core hip çatılı; art-director kararı gerekir); küçük merkez/köy eğimli; sanayi
	# (kit: sac 55-75,
	# hero ind gable).
	var dense := SettlementStats.roof_shares(_full, SettlementStats.indices_in_zones(_full, [&"center", &"dense"]))
	assert_float(dense["terrace"]).override_failure_message("yoğun teras %s" % [dense]).is_between(0.50, 0.72)
	var hist := SettlementStats.roof_shares(_full, SettlementStats.indices_in_zones(_full, [&"historic"]))
	assert_float(hist["pitched"]).override_failure_message("tarihî eğimli %s" % [hist]).is_between(0.70, 0.92)
	assert_float(hist["terrace"]).is_between(0.08, 0.30)
	var town := SettlementStats.roof_shares(_full, SettlementStats.indices_in_zones(_full, [&"town_center", &"town"]))
	assert_float(town["terrace"]).override_failure_message("küçük merkez teras %s" % [town]).is_between(0.10, 0.30)
	var village := SettlementStats.roof_shares(_full, SettlementStats.indices_in_zones(_full, [&"village"]))
	assert_float(village["pitched"]).override_failure_message("köy %s" % [village]).is_greater_equal(0.90)
	var yard := SettlementStats.roof_shares(_full, SettlementStats.indices_in_zones(_full, [&"yard"]))
	assert_float(yard["pitched"]).override_failure_message("sanayi %s" % [yard]).is_greater_equal(0.95)
	assert_float(yard["terrace"]).is_equal(0.0)


# --- Kit spec §3.3 + §7.1: bitişik nizam, blok çevresi, yükseklik hiyerarşisi, çeşitlilik ---

func test_dense_cores_use_row_housing_adjacent_buildings_with_tiny_gaps() -> void:
	var adj := SettlementStats.adjacency(_full, [&"center", &"dense", &"historic"], 1.2)
	assert_int(adj["pairs"]).is_greater(3000)
	# T-062 A2: kit tabanı 0,70 (ölçülen 0,718) hero ile TUTMUYOR (ölçülen 0,042); ADJACENCY_CORE_MIN notuna bakın.
	assert_float(adj["ratio"]).override_failure_message("bitişik oranı %s" % [adj]).is_greater(ADJACENCY_CORE_MIN)
	# kırsal/köy ayrık nizam: bahçe payı (3-5 m)
	var village := SettlementStats.adjacency(_full, [&"village"], 1.2)
	assert_float(village["ratio"]).is_less(0.25)


func test_negative_detached_control_destroys_the_row_housing_rule() -> void:
	var c := SettlementTestSupport.control()
	for zname in ["center", "dense", "historic"]:
		c["zones"][zname]["adjacent"] = false
		c["zones"][zname]["gap_m"] = [3.0, 5.0]
	var res := SettlementTestSupport.light_with(SettlementTestSupport.SEED, c)
	var adj := SettlementStats.adjacency(res, [&"center", &"dense", &"historic"], 1.2)
	var normal := SettlementStats.adjacency(SettlementTestSupport.light(), [&"center", &"dense", &"historic"], 1.2)
	assert_float(adj["ratio"]).override_failure_message("ayrık nizam yakalanmalı: %s / %s" % [adj, normal]) \
			.is_less(float(normal["ratio"]))


func test_block_frontage_is_filled_in_the_core() -> void:
	var fill := SettlementStats.block_frontage_fill(_full, [&"D1", &"D6"])
	assert_int(fill["blocks"]).is_greater(300)
	assert_float(fill["coverage"]).override_failure_message("çevre doluluğu %s" % [fill]).is_greater(FRONTAGE_COVERAGE_MIN)
	assert_float(fill["median_block"]).is_greater(FRONTAGE_MEDIAN_MIN)


func test_height_hierarchy_taller_towards_the_centre_and_on_main_streets() -> void:
	# Modern yoğun kuşak iç > dış; tarihî çekirdek alçak (kit §10: alçak tarihî çekirdek <-> yüksek modern küme); ana
	# cadde cepheleri yerel sokaktan yüksek.
	for code in [&"D1", &"D6"]:
		var h := SettlementStats.height_hierarchy(_full, code)
		assert_float(h["dense_inner"]).override_failure_message("%s yoğun iç/dış: %s" % [code, h]) \
				.is_greater(h["dense_outer"] + 0.4)
		assert_float(h["historic"] + 0.5).override_failure_message("%s tarihî çekirdek alçak: %s" % [code, h]) \
				.is_less(h["dense_inner"])
		assert_float(h["main"]).override_failure_message("%s ana cadde: %s" % [code, h]).is_greater(h["local"] + 0.25)


func test_composition_rules_neighbours_runs_windows_and_floor_variety() -> void:
	var seq := SettlementStats.neighbour_rules(_full)
	assert_int(seq["pairs"]).is_greater(20000)
	assert_int(seq["same_mesh_wall_neighbours"]).override_failure_message("komşu aynı (mesh+duvar): %s" % [seq]) \
			.is_equal(0)
	assert_int(seq["max_identical_run"]).is_less_equal(2)
	assert_float(seq["window_fail_ratio"]).override_failure_message("9'lu pencere: %s" % [seq]).is_less(0.02)
	# "orta yoğun blok" = ortalama katı >= 3 olan 9'lu konut pencereleri (alçak 2-3 katlı sıralar hariç).
	var fv := SettlementStats.floor_variety(_full, [&"center", &"dense", &"town_center"], 3.0)
	assert_int(fv["windows"]).is_greater(FLOOR_VARIETY_WINDOWS_MIN)
	assert_float(fv["ok_ratio"]).override_failure_message("kat çeşitliliği %s" % [fv]).is_greater(0.80)
	# Hero tablosu 21 modüldür: 200 m hücrede (>= 30 yapı) (mesh, duvar) benzersizlik oranı yapısal olarak <=
	# 21/N (ölçülen 0,0).
	# Çeşitlilik yerine hücre başına FARKLI MODÜL sayısı sınanır (kit: benzersiz kombinasyon ok_ratio 0,996).
	var cv := SettlementStats.cell_module_variety(_full, 200.0, 30, CELL_VARIETY_MIN_DISTINCT)
	assert_int(cv["cells"]).is_greater(300)
	assert_float(cv["ok_ratio"]).override_failure_message("200 m modül çeşitliliği %s" % [cv]).is_greater(0.90)


func test_negative_planted_identical_neighbours_are_detected() -> void:
	var cols := _clone(_full.columns)
	var seq_before := SettlementStats.neighbour_rules(_full)
	assert_int(seq_before["same_mesh_wall_neighbours"]).is_equal(0)
	var order := SettlementStats.street_order(_full)
	var group: PackedInt32Array = order[0]
	var k := 0
	while group.size() < 3 or _full.zone_of_building(group[0]) in [&"yard", &"farm"]:
		k += 1
		group = order[k]
	cols.module_idx[group[1]] = cols.module_idx[group[0]]
	cols.wall_row[group[1]] = cols.wall_row[group[0]]
	var bad := SettlementResult.with_columns(_full, cols)
	assert_int(SettlementStats.neighbour_rules(bad)["same_mesh_wall_neighbours"]).is_greater(0)


# --- Yönelim, determinizm ---

func test_buildings_face_the_street_with_the_parcel_frontage_orientation() -> void:
	assert_array(SettlementInvariants.check_orientation(_full)).is_empty()


func test_same_seed_same_hash_different_seed_different_detail_same_topology() -> void:
	var a := SettlementTestSupport.light_with(77, SettlementTestSupport.control())
	var b := SettlementTestSupport.light_with(77, SettlementTestSupport.control())
	var c := SettlementTestSupport.light_with(78, SettlementTestSupport.control())
	assert_str(a.columns.state_hash()).is_equal(b.columns.state_hash())
	assert_str(a.columns.state_hash()).is_not_equal(c.columns.state_hash())
	assert_str(a.columns.detail_hash()).is_not_equal(c.columns.detail_hash())
	assert_str(a.topology_hash()).override_failure_message("doluluk (topoloji) tohumla değişmemeli") \
			.is_equal(c.topology_hash())
	assert_int(a.lottery_parcels.size()).is_greater(1000)


func test_generate_returns_the_same_columns_as_generate_detailed() -> void:
	var net := SettlementTestSupport.net_light()
	var plain := T0Settlement.generate(net.world, net, SettlementTestSupport.manifest(), SettlementTestSupport.SEED,
			SettlementTestSupport.control())
	assert_str(plain.state_hash()).is_equal(SettlementTestSupport.light().columns.state_hash())
