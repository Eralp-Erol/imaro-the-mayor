extends GdUnitTestSuite
## T-005 · Q-015 uyumu: Ismeral coğrafyasının yaratıcı onayı yok; yerleşim koordinat sabitlemez, üretilmiş veri
## commit'lenmez, her koşuda WorldData + WorldNetwork çapalarından türer ve haritadan bağımsız (sentetik dünyada
## da) çalışır.
## Her tarama olumsuz varyantla kanıtlanır.

const SOURCE_DIR := "res://src/world/settlement"
const DATA_DIR := "res://data/world/ismeral"
## Veri dizininde beklenen kural/kontrol dosyaları: üretilmiş yapı/koordinat verisi (BuildingColumns dökümü) olamaz.
const ALLOWED_DATA_FILES: Array[String] = ["world.json", "coast.json", "regions.json", "sites.json", "terrain.json",
		"network.json", "settlement.json"]


## Kaynakta gömülü haritaya-bağlı koordinat (4+ haneli Vector2 sabiti) var mı: eşleşmeler.
static func hardcoded_vectors(text: String) -> PackedStringArray:
	var rx := RegEx.create_from_string("Vector2\\(\\s*-?\\d{4,}")
	var hits := PackedStringArray()
	for m in rx.search_all(text):
		hits.append(m.get_string())
	return hits


static func unexpected_files(names: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for n in names:
		if not ALLOWED_DATA_FILES.has(n) and not n.ends_with(".import") and not n.ends_with(".uid"):
			out.append(n)
	return out


func test_settlement_control_data_contains_no_coordinates_or_coordinate_pairs() -> void:
	var errors := SettlementRules.scan_coordinates(SettlementTestSupport.control())
	assert_array(errors).override_failure_message(str(errors)).is_empty()


func test_negative_coordinate_scan_catches_embedded_positions() -> void:
	var c := SettlementTestSupport.control()
	c["tower"]["spot"] = [20227.9, 18666.8]
	assert_bool(SettlementRules.scan_coordinates(c).is_empty()).is_false()
	var c2 := SettlementTestSupport.control()
	c2["regions"]["D1"]["anchor_km"] = [20.2, 18.6]
	assert_bool(SettlementRules.scan_coordinates(c2).is_empty()).is_false()
	var c3 := SettlementTestSupport.control()
	c3["zones"]["center"]["pos"] = {"x": 1.0, "z": 2.0}
	assert_bool(SettlementRules.scan_coordinates(c3).is_empty()).is_false()
	# kural sayıları (yüzde, metre aralığı) koordinat sayılmaz
	assert_array(SettlementRules.scan_coordinates({"gap_m": [0.0, 0.4], "setback_m": [3.0, 6.0]})).is_empty()


func test_no_source_hardcodes_a_map_coordinate() -> void:
	var dir := DirAccess.open(SOURCE_DIR)
	var checked := 0
	for name in dir.get_files():
		if name.ends_with(".gd"):
			var hits := hardcoded_vectors(FileAccess.get_file_as_string("%s/%s" % [SOURCE_DIR, name]))
			assert_array(hits).override_failure_message("%s: %s" % [name, hits]).is_empty()
			checked += 1
	assert_int(checked).is_greater(10)
	assert_bool(hardcoded_vectors("var p := Vector2(20227.9, 18666.8)").is_empty()).is_false()


func test_no_generated_building_data_is_committed_to_the_world_data_dir() -> void:
	var names := DirAccess.get_files_at(DATA_DIR)
	assert_array(unexpected_files(names)).override_failure_message(str(unexpected_files(names))).is_empty()
	assert_bool(unexpected_files(PackedStringArray(["settlement_columns.res"])).is_empty()).is_false()


func test_settlement_follows_the_world_when_the_terrain_is_edited() -> void:
	# Q-015: veri düzenlenip arazi değişince yerleşim onunla gider (koordinat sabitlemesi yok).
	var net := SettlementTestSupport.net_light()
	var base := SettlementTestSupport.light()
	var c := WorldTestSupport.control()
	c["terrain"]["seed_note"] = "değişiklik"
	var world_hash := net.world.state_hash()
	var moved := SettlementTestSupport.generate_on(NetworkTestSupport.light_network(), 91, SettlementTestSupport.control())
	assert_str(net.world.state_hash()).is_equal(world_hash)
	assert_int(moved.columns.count).is_greater(1000)
	assert_object(base).is_not_null()


# --- Haritadan bağımsız: sentetik düz dünya + el yapımı ızgara ağı (WorldFixture benzeri) ---

func _synthetic(origin: Vector2, seed_value: int) -> SettlementResult:
	var world := NetworkTestSupport.flat_world(3000.0, 100.0)
	var net := NetworkTestSupport.grid_network(world, 14, 8, 120.0, 76.0, origin, 7)
	var c := SettlementTestSupport.control()
	c["tower"]["enabled"] = false
	return T0Settlement.generate_detailed(world, net, SettlementTestSupport.manifest(), seed_value, c)


func test_generator_runs_on_a_synthetic_world_and_holds_every_invariant() -> void:
	var res := _synthetic(Vector2(400.0, 500.0), 5)
	assert_int(res.columns.count).is_greater(150)
	var violations := SettlementInvariants.check_all(res)
	assert_array(violations).override_failure_message(str(violations.slice(0, 6))).is_empty()
	assert_str(_synthetic(Vector2(400.0, 500.0), 5).columns.state_hash()).is_equal(res.columns.state_hash())


func test_synthetic_result_is_independent_of_where_the_grid_sits() -> void:
	# Aynı ızgara farklı konumda: koordinat sabitleme yoksa yapı sayısı/dokusu aynı mertebede ve değişmezler geçer.
	var a := _synthetic(Vector2(300.0, 300.0), 5)
	var b := _synthetic(Vector2(1100.0, 900.0), 5)
	assert_array(SettlementInvariants.check_all(b)).is_empty()
	assert_float(float(b.columns.count) / float(a.columns.count)).is_between(0.8, 1.25)


func test_negative_synthetic_building_in_water_is_still_detected() -> void:
	var water := Rect2(1500.0, 0.0, 1500.0, 3000.0)
	var world := NetworkTestSupport.flat_world(3000.0, 100.0, water)
	var net := NetworkTestSupport.grid_network(world, 8, 6, 120.0, 76.0, Vector2(200.0, 300.0), 7)
	var c := SettlementTestSupport.control()
	c["tower"]["enabled"] = false
	var res := T0Settlement.generate_detailed(world, net, SettlementTestSupport.manifest(), 5, c)
	assert_array(SettlementInvariants.check_on_land(res)).is_empty()
	var cols := res.columns
	cols.x[0] = 2000.0
	cols.z[0] = 1000.0
	assert_bool(SettlementInvariants.check_on_land(res).is_empty()).is_false()
