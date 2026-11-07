extends SimTestBase
## T-078 · Genel `SimFacadeImpl.attach_system`: isteğe bağlı sistem (+ komut işleyicisi) takma kapısı. Takılmazsa hiçbir
## şey değişmez (hash aynı); geçersiz takma ATOMİK reddedilir (yarım takılı sistem kalmaz).

const PROBE_KIND := &"t078.probe"


class ProbeSystem:
	extends SimSystem
	var _id: StringName

	func _init(id: StringName) -> void:
		_id = id

	func system_id() -> StringName:
		return _id

	func on_daily(state: GameState) -> void:
		var data := state.system_data(_id)
		data["days"] = int(data.get("days", 0)) + 1


class ProbeHandler:
	extends CommandHandler

	func command_type() -> StringName:
		return PROBE_KIND


func _facade() -> SimFacadeImpl:
	return FacadeTestSupport.facade()


func test_attached_system_runs_each_tick_and_changes_hash() -> void:
	var plain := _facade()
	var attached := _facade()
	assert_bool(attached.attach_system(ProbeSystem.new(&"t078_probe"))).is_true()
	plain.advance(3)
	attached.advance(3)
	assert_int(int((attached.game_state().systems["t078_probe"] as Dictionary)["days"])).is_equal(3)
	assert_str(attached.state_hash()).is_not_equal(plain.state_hash())


func test_unattached_facade_is_unchanged_by_the_feature() -> void:
	var a := _facade()
	var b := _facade()
	a.advance(5)
	b.advance(5)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_bool(a.game_state().systems.has("t078_probe")).is_false()


func test_attach_with_handler_registers_command_type() -> void:
	var facade := _facade()
	var handlers: Array[CommandHandler] = [ProbeHandler.new()]
	assert_bool(facade.attach_system(ProbeSystem.new(&"t078_probe"), handlers)).is_true()
	assert_bool(facade.simulation().handler_for(PROBE_KIND) != null).is_true()


func test_null_system_is_rejected() -> void:
	var facade := _facade()
	var ok := [true]
	await assert_error(func() -> void: ok[0] = facade.attach_system(null)) \
		.is_push_error("SimFacadeImpl: attach_system: sistem yok")
	assert_bool(ok[0]).is_false()


func test_duplicate_system_id_is_rejected_without_side_effects() -> void:
	var facade := _facade()
	assert_bool(facade.attach_system(ProbeSystem.new(&"t078_probe"))).is_true()
	var count_before := facade.simulation().system_count()
	var ok := [true]
	await assert_error(func() -> void: ok[0] = facade.attach_system(ProbeSystem.new(&"t078_probe"))) \
		.is_push_error("SimFacadeImpl: attach_system: 't078_probe' sistemi zaten takılı ya da kimliği geçersiz")
	assert_bool(ok[0]).is_false()
	assert_int(facade.simulation().system_count()).is_equal(count_before)


func test_conflicting_handler_rejects_whole_attach_atomically() -> void:
	var facade := _facade()
	var handlers: Array[CommandHandler] = [ProbeHandler.new()]
	assert_bool(facade.attach_system(ProbeSystem.new(&"t078_a"), handlers)).is_true()
	var count_before := facade.simulation().system_count()
	var ok := [true]
	var again: Array[CommandHandler] = [ProbeHandler.new()]
	await assert_error(func() -> void: ok[0] = facade.attach_system(ProbeSystem.new(&"t078_b"), again)) \
		.is_push_error("SimFacadeImpl: attach_system: 't078.probe' komut türü zaten kayıtlı ya da geçersiz")
	assert_bool(ok[0]).is_false()
	assert_int(facade.simulation().system_count()).is_equal(count_before)
	facade.advance(1)
	assert_bool(facade.game_state().systems.has("t078_b")).is_false()


func test_attach_after_ticks_started_is_rejected() -> void:
	var facade := _facade()
	facade.advance(1)
	var ok := [true]
	await assert_error(func() -> void: ok[0] = facade.attach_system(ProbeSystem.new(&"t078_probe"))) \
		.is_push_error("SimFacadeImpl: attach_system: tick ilerlemiş (sistemler yalnız tick 0'da takılır)")
	assert_bool(ok[0]).is_false()
