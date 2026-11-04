extends GdUnitTestSuite
## B-009 · Yıkım kaydı (`works[i].kind == "demolish"`, ops'ta `remove_edge`, `pts_cm` YOK) "yeni yol" ya da "yol
## geometrisi" sayılmaz: `PriorityReview.new_roads` / `road_polylines` yalnız AYAKTA duran yolları okur. Eski
## davranış: yıkımdan sonraki ilk tick'te `new_roads` yıkım satırının `pts_cm`ini okuyup motor hatası veriyordu ve o
## tick'in gerçek yeni yol tetikleyicisi atlanıyordu.

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const BUILD_TICK := 5
const DEMOLISH_TICK := 8


## Yol (komut 1, tick 5) + o yolun yıkımı (komut 2, tick 8; iki kenar = iki satır) olan çıplak durum.
func _state_with_demolition() -> GameState:
	var state := GameState.new()
	state.tick = BUILD_TICK
	_add_road(state, 1, [[0, 0], [10000, 0]])
	state.tick = DEMOLISH_TICK
	var remove := PublicWorksState.OP_REMOVE_EDGE
	var ops: Array = [{"op": remove, "edge": 11}, {"op": remove, "edge": 12}]
	PublicWorksState.append_demolition(state, 2, 1, "local", ops, ["h1", "h2"])
	return state


func _add_road(state: GameState, command_id: int, pts: Array) -> void:
	var op := {"op": "add_road", "pts_cm": pts, "class": "local", "width_dm": 100}
	var work := {"command_id": command_id, "tick": state.tick, "road_class": "local", "length_cm": 10000,
		"region_units": {}}
	PublicWorksState.append_work(state, "base", op, "h%d" % command_id, work)


func test_new_roads_skips_the_demolition_rows_of_the_previous_tick() -> void:
	var state := _state_with_demolition()
	state.tick = DEMOLISH_TICK + 1  # yıkım komutu bir önceki tick'te uygulandı
	assert_array(PriorityReview.new_roads(state)).is_empty()


func test_new_roads_still_lists_a_real_road_built_in_the_same_tick_as_a_demolition() -> void:
	var state := _state_with_demolition()
	state.tick = DEMOLISH_TICK  # aynı tick'te yeni yol: yıkım satırları arasında kalmamalı
	_add_road(state, 3, [[0, 500], [10000, 500]])
	state.tick = DEMOLISH_TICK + 1
	var roads := PriorityReview.new_roads(state)
	assert_int(roads.size()).is_equal(1)
	assert_int(int(roads[0]["command_id"])).is_equal(3)
	assert_array(roads[0]["pts"]).is_equal([[0, 500], [10000, 500]])


func test_new_roads_does_not_list_a_road_demolished_in_the_same_tick_it_was_built() -> void:
	var state := GameState.new()
	state.tick = DEMOLISH_TICK
	_add_road(state, 1, [[0, 0], [10000, 0]])
	PublicWorksState.append_demolition(state, 2, 1, "local", [{"op": PublicWorksState.OP_REMOVE_EDGE, "edge": 11}],
		["h"])
	state.tick = DEMOLISH_TICK + 1
	assert_array(PriorityReview.new_roads(state)).is_empty()


func test_road_polylines_lists_only_standing_roads_and_ignores_demolition_ops() -> void:
	var state := _state_with_demolition()
	assert_array(PriorityReview.road_polylines(state)).is_empty()  # tek yol yıkıldı: erişim yok
	_add_road(state, 3, [[0, 500], [10000, 500]])
	assert_array(PriorityReview.road_polylines(state)).is_equal([[[0, 500], [10000, 500]]])


## Uçtan uca: gerçek yol komutu + gerçek yıkım komutu; sonraki tick'ler hatasız ve yıkım yeni yol sayılmaz.
func test_a_real_demolition_then_ticks_neither_errors_nor_queues_the_demolished_road() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, E.NEAR_A)
	f.advance(40)
	var built := E.road_a(f)
	f.advance(1)
	assert_int(E.queue(f).size()).is_greater(0)  # yol gerçekten tetikleyici
	E.eco(f)["priority"] = {}  # kuyruğu boşalt: yıkım sonrası yeniden dolmadığını ölçmek için
	E.eco(f)["priority_cmd"] = {}
	var demolished := f.submit_command(SimCommand.public_work_demolish(built.command_id))
	assert_bool(demolished.is_rejected()).is_false()
	f.advance(3)  # yıkım tick'i + sonraki tick: new_roads yıkım satırlarını görür
	assert_int(f.public_works().size()).is_equal(0)
	assert_dict(E.queue(f)).override_failure_message("yıkım yeni yol tetikleyicisi sayıldı").is_empty()
	assert_array(PriorityReview.new_roads(f.game_state())).is_empty()


## Yıkımdan SONRA yürürlüğe giren plan: erişim yolu artık yok, parseller kuyruğa değil eski dikkat yoluna gider.
func test_a_plan_taking_effect_after_the_only_road_was_demolished_routes_to_attention_not_the_queue() -> void:
	var run := E.setup()
	var f := E.f(run)
	var built := E.road_a(f)
	f.advance(2)
	f.submit_command(SimCommand.public_work_demolish(built.command_id))
	f.advance(2)
	E.eco(f)["priority"] = {}
	E.eco(f)["priority_cmd"] = {}
	E.plan(f, [1, 2, 3])  # küçük plan: meclis eşiğinin altında, hemen yürürlüğe girer
	f.advance(3)
	assert_int(f.public_works().size()).is_equal(0)
	assert_dict(E.queue(f)).override_failure_message("yıkık yola bağlı sayıldı").is_empty()
	assert_int((E.eco(f)["attention"] as Dictionary).size()).override_failure_message("plan dikkat yoluna girmedi") \
		.is_greater(0)
