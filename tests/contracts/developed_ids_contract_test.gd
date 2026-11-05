extends GdUnitTestSuite
## Sözleşme 1.10 (B-052, ADR-0011; ADR-0005 Ek M) · `SimFacade.sim_developed_parcel_ids()`:
## `ParcelView.developed_by_sim` olan TÜM parsellerin kimlikleri (artan, tekrarsız). Salt okunur sorgu:
## durum/hash/kayıt biçimi DEĞİŞMEZ. Taban sınıf varsayılanı DOĞRU (yavaş) yoldur (`parcel_ids` + `parcel_views`
## süzgeci); `SimFacadeImpl` hızlı yolu ezer. Bu dosya: sürüm, hızlı yol == bağımsız süzgeç (taze/orta oyun/
## kayıt-yükle), saflık, mock varsayılanı.

const S := preload("res://tests/contracts/contract_test_support.gd")
const M := preload("res://tests/sim/m2_support.gd")
const SLICE := 400


## Bağımsız referans: tüm parseller dilimli okunur, `developed_by_sim` süzülür (taban varsayılanın tanımı).
func _reference(f: SimFacade) -> PackedInt64Array:
	var out := PackedInt64Array()
	var all := f.parcel_ids()
	var pos := 0
	while pos < all.size():
		var chunk := all.slice(pos, mini(pos + SLICE, all.size()))
		pos += chunk.size()
		for v in f.parcel_views(chunk):
			if v.developed_by_sim:
				out.append(v.id)
	return out


func _assert_sorted_unique(ids: PackedInt64Array) -> void:
	for i in range(1, ids.size()):
		assert_int(ids[i]).override_failure_message("kimlikler artan/tekrarsız değil (%d)" % i).is_greater(ids[i - 1])


func test_contract_version_is_1_10_and_the_query_is_in_the_facade_surface() -> void:
	assert_str(SimContract.VERSION).is_equal("1.10")
	assert_int(SimContract.VERSION_MAJOR).is_equal(1)
	assert_int(SimContract.VERSION_MINOR).is_equal(10)
	for older in ["1.0", "1.8", "1.9", "1.10"]:
		assert_bool(SimContract.is_compatible(older)).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()
	assert_bool(SimContract.is_compatible("1.x")).is_false()
	assert_bool(MockSimFacade.new().has_method(&"sim_developed_parcel_ids")).is_true()


func test_fresh_world_has_no_developed_parcels() -> void:
	var h := M.politics_handle(M.ISOLATE, 6)
	var f := h.facade
	assert_int(f.sim_developed_parcel_ids().size()).is_equal(0)
	assert_int(_reference(f).size()).is_equal(0)
	f.advance(3)
	assert_int(f.sim_developed_parcel_ids().size()).is_equal(0)


func test_mid_game_fast_path_equals_the_independent_filter() -> void:
	var f := M.stress_run(M.SEED, 120)
	var ref := _reference(f)
	assert_int(ref.size()).override_failure_message("senaryo yapılı parsel üretmedi: test anlamsız").is_greater(0)
	var ids := f.sim_developed_parcel_ids()
	assert_array(Array(ids)).is_equal(Array(ref))
	_assert_sorted_unique(ids)


func test_a_declined_parcel_and_untouched_parcels_are_not_listed() -> void:
	var run := M.two_conditions_run()
	var f: SimFacadeImpl = run["facade"]
	var ids := f.sim_developed_parcel_ids()
	assert_bool(ids.has(int(run["approved_parcel"]))).is_true()
	assert_bool(ids.has(int(run["declined_parcel"]))).is_false()
	assert_array(Array(ids)).is_equal(Array(_reference(f)))
	assert_int(ids.size()).override_failure_message("yalnız onaylanan parsel yapılı olmalı").is_less(f.parcel_ids().size())


func test_every_stage_a_developed_parcel_can_be_in_is_listed_while_the_sim_runs() -> void:
	# Planlı, inşaatta, yapıldı: liste her günde bağımsız süzgeçle eşit; sorgu aşamayı ayırmaz.
	var h := M.politics_handle(M.ISOLATE, 6)
	var f := h.facade
	var p1 := int(f.parcel_ids()[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p1]), &"zone.mixed"))
	var seen_stages := {}
	for _day in 200:
		f.advance(1)
		seen_stages[String(f.parcel_views(PackedInt64Array([p1]))[0].development)] = true
		assert_array(Array(f.sim_developed_parcel_ids())).is_equal(Array(_reference(f)))
	for stage in ["planned", "under_construction", "built"]:
		assert_bool(seen_stages.has(stage)).override_failure_message("aşama görülmedi: " + stage).is_true()
	assert_array(Array(f.sim_developed_parcel_ids())).is_equal([p1])


func test_the_query_is_read_only_state_hash_and_save_bytes_are_unchanged() -> void:
	var f := M.stress_run(M.SEED, 60)
	var hash_before := f.state_hash()
	var bytes_before := f.export_save()
	var obs_before := S.observable_hash(f)
	for _i in 3:
		f.sim_developed_parcel_ids()
	assert_str(f.state_hash()).is_equal(hash_before)
	assert_str(S.observable_hash(f)).is_equal(obs_before)
	assert_bool(f.export_save() == bytes_before).override_failure_message("kayıt baytları değişti").is_true()


func test_returned_array_is_a_value_copy() -> void:
	var f := M.stress_run(M.SEED, 60)
	var first := f.sim_developed_parcel_ids()
	assert_int(first.size()).is_greater(0)
	var expected := Array(first)
	first.clear()
	assert_array(Array(f.sim_developed_parcel_ids())).is_equal(expected)


func test_after_save_and_load_the_list_is_identical() -> void:
	var f := M.stress_run(M.SEED, 90)
	var before := f.sim_developed_parcel_ids()
	assert_int(before.size()).is_greater(0)
	var bytes := f.export_save()
	var f2 := M.politics_handle(M.E.regions(M.STRESS), 14).facade
	assert_int(f2.sim_developed_parcel_ids().size()).override_failure_message("taze dünya boş olmalı").is_equal(0)
	var r := (f2 as SimFacadeImpl).import_save(bytes)
	assert_bool(r.ok).override_failure_message(r.message).is_true()
	assert_array(Array(f2.sim_developed_parcel_ids())).is_equal(Array(before))
	assert_array(Array(f2.sim_developed_parcel_ids())).is_equal(Array(_reference(f2)))


func test_a_facade_without_economy_gives_an_empty_list() -> void:
	# Ekonomisiz facade (yalnız parsel kaynağı): sorgu boş döner ve çökmez.
	var f := FacadeTestSupport.facade()
	assert_int(f.sim_developed_parcel_ids().size()).is_equal(0)
	assert_int(_reference(f).size()).is_equal(0)


# --- Taban sınıf varsayılanı (mock: sorguyu ezmez, doğru yavaş yolu kullanır) ---

func test_mock_facade_uses_the_correct_default_path() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_int(f.sim_developed_parcel_ids().size()).is_equal(_reference(f).size())
	# Mock'ta yapılı parseller koyarak varsayılan süzgeç doğrulanır (özel alan: test tohumlar).
	var ids := f.parcel_ids()
	assert_int(ids.size()).is_greater_equal(3)
	var want := PackedInt64Array([ids[0], ids[2]])
	for id in want:
		(f._parcels[int(id)] as ParcelView).developed_by_sim = true
	assert_array(Array(f.sim_developed_parcel_ids())).is_equal(Array(want))
	_assert_sorted_unique(f.sim_developed_parcel_ids())
	assert_array(Array(f.sim_developed_parcel_ids())).is_equal(Array(_reference(f)))
	# Değer kopyası: dönen dizi mock'u etkilemez
	var got := f.sim_developed_parcel_ids()
	got.clear()
	assert_int(f.sim_developed_parcel_ids().size()).is_equal(2)


func test_contract_checks_cover_the_query_for_mock_and_real_facades() -> void:
	var mock := S.facade(S.SCENARIO_POSITIVE)
	assert_array(SimContractChecks.check_facade(mock)).is_empty()
	var real := M.stress_run(M.SEED, 40)
	assert_array(SimContractChecks.check_facade(real)).is_empty()
	# Negatif: ihlal yakalanır (liste süzgeçle uyuşmazsa denetim satır döner).
	var bad := SimContractChecks.check_developed_ids(real, PackedInt64Array([1, 1]))
	assert_int(bad.size()).is_greater(0)
