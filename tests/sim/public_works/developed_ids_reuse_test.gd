extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## B-052 (ADR-0011) · `sim_developed_parcel_ids()` kamulaştırma -> yıkım -> belediye arazisi imarı -> yeniden
## yapılaşma yolunda: T0 stoğundan gelen parsel, arsa geri açılıp yatırımcı yapı verdikten sonra listededir (T0
## ayrımı yok); kamulaştırılmış (alınmış) ve boş parseller listede değildir; hızlı yol bağımsız süzgeçle eşit;
## kayıt-yükle sonrası eşit.


func _reference(f: SimFacadeImpl) -> PackedInt64Array:
	var out := PackedInt64Array()
	var all := f.parcel_ids()
	var pos := 0
	while pos < all.size():
		var chunk := all.slice(pos, mini(pos + 400, all.size()))
		pos += chunk.size()
		for v in f.parcel_views(chunk):
			if v.developed_by_sim:
				out.append(v.id)
	return out


func _redeveloped_run() -> Dictionary:
	var run := _land_demolished()
	var f := _land_f(run)
	# Yıkımdan hemen sonra: arsa belediyede (alınmış), liste boş (T0 stoku sim yapısı sayılmaz).
	assert_array(Array(f.sim_developed_parcel_ids())).is_empty()
	_land_do(run, _land_command(run["taken"], &"zone.residential"))
	var developed := PackedInt64Array()
	for _day in 220:
		f.advance(1)
		developed = f.sim_developed_parcel_ids()
		assert_array(Array(developed)).is_equal(Array(_reference(f)))
	run["developed"] = developed
	return run


func test_a_released_stock_parcel_the_investor_rebuilds_is_in_the_list() -> void:
	var run := _redeveloped_run()
	var developed: PackedInt64Array = run["developed"]
	var taken: PackedInt64Array = run["taken"]
	var overlap := 0
	for id in taken:
		overlap += 1 if developed.has(id) else 0
	assert_int(overlap).override_failure_message(
			"yeniden imarlı T0 parseli yatırımcı yapısı almadı: test anlamsız (liste %d)" % developed.size()).is_greater(0)
	for i in range(1, developed.size()):
		assert_int(developed[i]).is_greater(developed[i - 1])


func test_the_list_does_not_include_taken_or_untouched_stock_parcels() -> void:
	var run := _land_setup()
	var f := _land_f(run)
	assert_array(Array(f.sim_developed_parcel_ids())).is_empty()
	_land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_assert_taken(run)
	assert_array(Array(f.sim_developed_parcel_ids())).override_failure_message("alınmış parsel listede").is_empty()
	assert_array(Array(_reference(f))).is_empty()


func test_the_query_does_not_change_state_hash_in_the_expropriation_flow_and_survives_save_load() -> void:
	var run := _redeveloped_run()
	var f := _land_f(run)
	var hash_before := f.state_hash()
	var list_before := f.sim_developed_parcel_ids()
	assert_str(f.state_hash()).is_equal(hash_before)
	var bytes := f.export_save()
	var fresh := _land_setup()
	var r := _land_f(fresh).import_save(bytes)
	assert_bool(r.ok).override_failure_message(r.message).is_true()
	assert_array(Array(_land_f(fresh).sim_developed_parcel_ids())).is_equal(Array(list_before))
	assert_array(Array(_land_f(fresh).sim_developed_parcel_ids())).is_equal(Array(_reference(_land_f(fresh))))
	assert_str(_land_f(fresh).state_hash()).is_equal(hash_before)
