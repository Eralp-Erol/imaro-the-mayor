extends "res://tests/sim/politics/reaction_world_base.gd"
## T-050 / TEK-01/02 · Yaşam görünümü sim'i YALNIZ OKUR: okuma çalışması sim durum özetini (state_hash) değiştirmez,
## okuyucu ile okuyucusuz ikiz dünya aynı özete varır; yaşam kodunda yazma/komut çağrısı yoktur. Parsel durumları
## T0 stokundan ve sim değişim akışından gelir (sahte sayı yok).

const LIFE_DIR := "res://src/view/life/"


func _stock() -> ListStockSource:
	return ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 2, "use": "residential", "units": 6, "owner": 1},
		{"parcel_id": 3, "use": "commercial", "units": 4, "owner": 1}])


func _reader(h: PoliticsHandle, net: WorldNetwork) -> LifeSimReader:
	var cfg := LifeConfig.load_default()
	var act := LifeEdgeActivity.create(net, cfg)
	return LifeSimReader.create(h.facade, act, net, _stock())


func _view(use: StringName, development: StringName, units: int) -> ParcelView:
	var v := ParcelView.new()
	v.id = 1
	v.use = use
	v.development = development
	v.units = units
	return v


func test_state_of_maps_development_to_activity_units() -> void:
	assert_vector(Vector3(LifeSimReader.state_of(_view(ParcelView.USE_RESIDENTIAL, ParcelView.DEVELOPMENT_BUILT, 8)))) \
			.is_equal(Vector3(8, 0, 0))
	assert_vector(Vector3(LifeSimReader.state_of(_view(ParcelView.USE_COMMERCIAL, ParcelView.DEVELOPMENT_BUILT, 3)))) \
			.is_equal(Vector3(0, 3, 0))
	var site := _view(ParcelView.USE_RESIDENTIAL, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, 5)
	assert_vector(Vector3(LifeSimReader.state_of(site))).is_equal(Vector3(0, 0, 5))
	for dev in [ParcelView.DEVELOPMENT_VACANT, ParcelView.DEVELOPMENT_PLANNED, ParcelView.DEVELOPMENT_STALLED,
			ParcelView.DEVELOPMENT_TAKEN]:
		assert_vector(Vector3(LifeSimReader.state_of(_view(ParcelView.USE_RESIDENTIAL, dev, 9)))).is_equal(Vector3.ZERO)
	assert_vector(Vector3(LifeSimReader.state_of(null))).is_equal(Vector3.ZERO)
	assert_vector(Vector3(LifeSimReader.state_of(_view(ParcelView.USE_RESIDENTIAL, ParcelView.DEVELOPMENT_BUILT, 0)))) \
			.is_equal(Vector3.ZERO)


func test_t0_stock_becomes_parcel_state_with_real_use_and_units() -> void:
	var w := _world(false)
	var reader := _reader(w["handle"], w["net"])
	var st := reader.activity.parcel_state
	assert_vector(Vector3(st[1])).is_equal(Vector3(10, 0, 0))
	assert_vector(Vector3(st[2])).is_equal(Vector3(6, 0, 0))
	assert_vector(Vector3(st[3])).is_equal(Vector3(0, 4, 0))
	assert_bool(st.has(4)).is_false()


func test_polling_the_real_sim_does_not_change_its_state_hash() -> void:
	var a := _world(false)
	var b := _world(false)
	var ha: PoliticsHandle = a["handle"]
	var hb: PoliticsHandle = b["handle"]
	var reader := _reader(ha, a["net"])
	assert_str(ha.facade.state_hash()).is_equal(hb.facade.state_hash())
	for _i in 20:
		ha.facade.advance(1)
		hb.facade.advance(1)
		reader.poll(false)
		reader.poll(false)
		var msg := "okuma sim durumunu değiştirdi (tick %d)" % ha.facade.current_tick()
		assert_str(ha.facade.state_hash()).override_failure_message(msg).is_equal(hb.facade.state_hash())
	assert_int(int(reader.stats["economy_reads"])).is_greater(0)


func test_tick_frames_do_no_parcel_reads_and_reads_are_capped_per_frame() -> void:
	var w := _world(false)
	var h: PoliticsHandle = w["handle"]
	var reader := _reader(h, w["net"])
	reader.parcels_per_frame = 2
	h.facade.advance(3)
	var before := int(reader.stats["views_read"])
	reader.poll(true)
	assert_int(int(reader.stats["views_read"])).is_equal(before)
	for _i in 10:
		var read_before := int(reader.stats["views_read"])
		reader.poll(false)
		assert_int(int(reader.stats["views_read"]) - read_before).is_less_equal(2)


func test_life_code_never_writes_to_the_sim() -> void:
	var forbidden := ["submit_command", "SimCommand", "attach_public_works", "attach_economy", "advance(", "set_speed",
			"apply_command", "state_hash"]
	var dir := DirAccess.open(LIFE_DIR)
	assert_object(dir).is_not_null()
	var seen := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		seen += 1
		var code := FileAccess.get_file_as_string(LIFE_DIR + f)
		for line in code.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("##") or stripped.begins_with("#"):
				continue
			for word in forbidden:
				var msg := "%s: yasak çağrı '%s': %s" % [f, word, stripped]
				assert_bool(stripped.contains(word)).override_failure_message(msg).is_false()
	assert_int(seen).is_greater(5)
