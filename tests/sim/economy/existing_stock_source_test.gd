extends SimTestBase
## T-013 ölçüt 2 · `ExistingStockSource`: T0 mevcut yapı stoğu arayüzü (T-005 `BuildingColumns` sonra takılır). Şimdilik
## boş ve liste (fixture) kaynakları; geçersiz girdi anlaşılır hatayla reddedilir.


func test_empty_source_has_no_stock() -> void:
	var src := EmptyStockSource.new()
	assert_int(src.parcel_ids().size()).is_equal(0)


func test_list_source_returns_sorted_ids_and_values() -> void:
	var src := ListStockSource.create([
		{"parcel_id": 9, "use": &"commercial", "units": 4, "owner": 2},
		{"parcel_id": 3, "use": &"residential", "units": 12, "owner": 0},
	])
	assert_bool(src.is_valid()).override_failure_message(str(src.errors)).is_true()
	assert_array(Array(src.parcel_ids())).is_equal([3, 9])
	assert_str(String(src.use_of(3))).is_equal("residential")
	assert_int(src.units_of(3)).is_equal(12)
	assert_int(src.owner_of(9)).is_equal(2)
	assert_int(src.units_of(404)).override_failure_message("bilinmeyen parsel 0 birim").is_equal(0)


func test_list_source_rejects_bad_entries_with_messages() -> void:
	var cases := {
		"duplicate": [{"parcel_id": 1, "use": &"residential", "units": 1, "owner": 0},
			{"parcel_id": 1, "use": &"residential", "units": 2, "owner": 0}],
		"bad id": [{"parcel_id": 0, "use": &"residential", "units": 1, "owner": 0}],
		"bad use": [{"parcel_id": 1, "use": &"spaceport", "units": 1, "owner": 0}],
		"no units": [{"parcel_id": 1, "use": &"residential", "units": 0, "owner": 0}],
		"negative owner": [{"parcel_id": 1, "use": &"residential", "units": 1, "owner": -1}],
	}
	for label: String in cases:
		var src := ListStockSource.create(cases[label])
		assert_bool(src.is_valid()).override_failure_message("%s kabul edildi" % label).is_false()
		assert_str(" ".join(src.errors)).override_failure_message("%s: hata metni boş" % label).is_not_empty()
		assert_int(src.parcel_ids().size()).override_failure_message("%s: geçersiz kaynak boş olmalı" % label).is_equal(0)
