extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## B-022 · Yıkılan yolun boş belediye arazisi "Yapılı parsel" (existing) diye etiketlenmez: plan durumu `unplanned`
## (yürürlükte plan yok, imara açılabilir). Yapılı parsel `existing` kalır. Yalnız türetilen etiket; durum değişmez.


func _plan(run: Dictionary, id: int) -> PlanStateView:
	return _land_f(run).plan_state(id)


func test_built_parcel_before_any_road_stays_existing() -> void:
	var run := _land_setup()
	for id in run["taken"]:
		var d := EconomyState.data(_land_f(run).game_state())
		assert_int(int(d["stage"][EconomyState.index_of(d, id)])).is_not_equal(EconomyState.STAGE_TAKEN)
		assert_str(String(_plan(run, id).state)).is_equal("existing")


func test_demolished_municipal_land_is_not_labelled_existing_and_is_open_for_planning() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var before := f.state_hash()
	for id in run["taken"]:
		var plan := _plan(run, id)
		assert_str(String(plan.state)).override_failure_message("parsel %d" % id).is_equal("unplanned")
		assert_bool(PlanStateText.needs_plan(plan)).is_true()
	assert_str(f.state_hash()).override_failure_message("sorgu durumu değiştirdi").is_equal(before)


func test_standing_road_strip_is_not_called_open_municipal_land() -> void:
	var run := _land_setup()
	_land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_assert_taken(run)
	for id in run["taken"]:
		assert_str(String(_plan(run, id).state)).is_not_equal("unplanned")


func test_municipal_land_plan_state_follows_the_proposal_then_the_applied_plan() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	_land_do(run, _land_command(run["taken"]))
	var first := int((run["taken"] as PackedInt64Array)[0])
	assert_str(String(_plan(run, first).state)).is_equal("proposed")
	f.advance(int(ParcelZoningSystem.overlay_of(f.game_state(), first)["due_tick"]) - f.current_tick())
	_land_assert_fresh_green(run)
	assert_str(String(_plan(run, first).state)).is_equal("planned")
