extends "res://tests/sim/politics/reaction_world_base.gd"
## T-042c (D-014 §1) · Geri alma penceresi ile siyaset: yol geri alınırsa o yola bağlı halk tepkisi (tepki defteri
## satırları) HİÇ olmamış gibi silinir; ama tepki siyaset taramasına (haftalık kesim taraması) girdiyse kesim durumu
## ve gündem zaten ondan etkilenmiştir -> yarım geri alma yapılmaz, geri alma `undo_window_closed` ile reddedilir.
## Düz yolda (tepki defteri yok) pencere tarama ile kapanmaz. `scan_blocs` yalnız kesim motorunu çalıştırır;
## haftalık sayaç (`counters.scans`) gerçek tick sürücüsünden gelir, bu yüzden `advance` kullanılır.

const SCAN_DAYS := 7


func test_undoing_before_any_scan_leaves_no_reaction_signal_behind() -> void:
	var h: PoliticsHandle = _world()["handle"]
	assert_bool(h.facade.undo_available()).is_true()
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(1)
	assert_str(String(h.facade.parcel_views(PackedInt64Array([1]))[0].development)).is_equal("built")
	assert_int(PublicWorksState.reaction_rows(h.state(), "displaced", "D1").size()).is_equal(0)
	scan_blocs(h)
	assert_int(_signal(h, "displacement")).override_failure_message("geri alınan yolun tepkisi kalmamalı") \
		.is_equal(0)
	assert_int(_signal(h, "proximity")).is_equal(0)


func test_the_window_closes_once_a_weekly_scan_has_consumed_the_reaction() -> void:
	var h: PoliticsHandle = _world()["handle"]  # yol tick 2'de uygulandı
	assert_bool(h.facade.undo_available()).is_true()
	h.facade.advance(SCAN_DAYS)  # tick 9: tick 7 taraması geçti
	assert_bool(h.facade.undo_available()).is_false()
	var r := h.facade.validate_command(SimCommand.public_work_undo_last())
	assert_str(String(r.status)).is_equal("rejected")
	assert_str(String(r.reason_key)).is_equal("public_work.reject.undo_window_closed")
	assert_str(String(r.args["cause"])).is_equal("reaction_recorded")
	# reddedilen geri alma hiçbir şeyi değiştirmez: yol, alınan parsel ve tepki durur
	var rows_before := PublicWorksState.reaction_rows(h.state(), "displaced", "D1").size()
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(1)
	assert_int(h.facade.public_works().size()).is_equal(1)
	assert_str(String(h.facade.parcel_views(PackedInt64Array([1]))[0].development)).is_equal("taken")
	assert_int(PublicWorksState.reaction_rows(h.state(), "displaced", "D1").size()).is_equal(rows_before)


func test_a_plain_road_stays_undoable_across_scans_because_it_has_no_reaction() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	h.facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	h.facade.advance(1)
	h.facade.advance(SCAN_DAYS * 3)
	assert_bool(h.facade.undo_available()).is_true()
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(1)
	assert_int(h.facade.public_works().size()).is_equal(0)


func test_the_reaction_probe_hook_can_close_the_window_for_the_reaction_layer() -> void:
	var world := _world()
	var h: PoliticsHandle = world["handle"]
	var ctx: PublicWorksContext = h.facade.public_works_context()
	var asked: Array[int] = []
	ctx.reaction_consumed = func(_state: GameState, command_id: int) -> bool:
		asked.append(command_id)
		return true
	assert_bool(h.facade.undo_available()).is_false()
	assert_array(asked).is_equal([h.facade.public_works()[0].command_id])
