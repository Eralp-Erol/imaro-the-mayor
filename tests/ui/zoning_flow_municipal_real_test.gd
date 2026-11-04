extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## T-066 / D-018: imar akışı modeli GERÇEK sim ve ağla: yıkılan yolun boş belediye arazisi -> açık imar kararı.


func _model(run: Dictionary) -> ZoningFlowModel:
	return ZoningFlowModel.create(_land_f(run))


func _feed(model: ZoningFlowModel, run: Dictionary) -> void:
	for event in _land_f(run).events_since(0):
		model.handle_event(event)


func test_real_sim_municipal_land_flow_goes_from_button_to_empty_green_parcels() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var model := _model(run)
	assert_array(Array(model.municipal_available_ids())).is_equal(Array(run["taken"]))
	assert_bool(model.use_municipal_land()).is_true()
	assert_bool(model.municipal_mode).is_true()
	model.choose_use(&"zone.green")
	var preview := model.preview()
	assert_bool(preview.ok).override_failure_message("önizleme: %s" % str(preview.reason)).is_true()
	assert_bool(model.can_send()).is_true()
	_land_assert_taken(run)  # gönderim öncesi hiçbir şey değişmez
	assert_bool(model.send()).is_true()
	f.advance(1)
	_feed(model, run)
	f.advance(12)
	_feed(model, run)
	_land_assert_fresh_green(run)
	assert_int(model.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)


func test_real_sim_standing_road_land_is_never_offered() -> void:
	var run := _land_setup()
	_land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	var model := _model(run)
	assert_int(model.municipal_available_ids().size()).is_equal(0)
	assert_bool(model.use_municipal_land()).is_false()
	assert_bool(model.municipal_mode).is_false()
