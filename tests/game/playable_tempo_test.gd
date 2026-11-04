extends GdUnitTestSuite
## T-043B C · Oynanabilir başlangıç hızı "hızlı" + tek seferlik hız ipucu (core-loop-v0 §3; ölçüt 5 UI yarısı, 6).
## Olumlu: başlangıç hızı hızlı; yol/plan olayı ipucu açar;
## Hızlandır/Kapat gerçek iş yapar; kapatılınca bir daha çıkmaz;
## gün sayacı görünür. Olumsuz: ilgisiz olay ipucu açmaz; zaten en hızlıyken ya da kapatılmışken açılmaz; oturumda
## ikinci kez çıkmaz. Hız sim durumu değildir: farklı hızlarda aynı tick sayısı aynı durum özetini verir.
## Gerçek facade (PoliticsBootstrap); olaylar HUD'a sentetik verilir (tetik tanıma sınaması, gerçek yol değildir).

const VIEWPORT := Vector2(1600.0, 900.0)

var _prefs_path: String = ""


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_prefs_path = "user://test_game_hints_%d.cfg" % Time.get_ticks_usec()


func after_test() -> void:
	UiText.reset()
	if FileAccess.file_exists(_prefs_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_prefs_path))


func _scene(max_speed: int = 4) -> Dictionary:
	var f := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(InputProfile.create(&"desktop"))
	hud.setup(f, UiTestSupport.platform(&"desktop", {"max_game_speed": max_speed}))
	hud.size = VIEWPORT
	hud.refresh()
	var prefs := PlayableHintPrefs.create(_prefs_path)
	var hint := PlayableTempo.attach(hud, f, prefs)
	return {"hud": hud, "facade": f, "hint": hint, "prefs": prefs}


func _road_event() -> SimEvent:
	var e := SimEvent.new()
	e.kind = SimEvent.KIND_PUBLIC_WORK_BUILT
	return e


func _zoning_event() -> SimEvent:
	var e := SimEvent.new()
	e.kind = SimEvent.KIND_PARCEL_CHANGED
	e.message_key = &"event.zoning.applied"
	return e


func _send(scene: Dictionary, event: SimEvent) -> void:
	var hud: HudRoot = scene["hud"]
	var events: Array[SimEvent] = [event]
	hud.events_received.emit(events)


# --- Başlangıç hızı ---

func test_start_speed_is_fast_in_playable() -> void:
	var s := _scene()
	var f: SimFacade = s["facade"]
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FAST)


func test_start_speed_respects_platform_cap() -> void:
	var s := _scene(1)
	var f: SimFacade = s["facade"]
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)


func test_pick_start_level_pure() -> void:
	var all := PackedInt32Array([0, 1, 2, 3])
	assert_int(PlayableTempo.pick_start_level(all, 3)).is_equal(2)
	assert_int(PlayableTempo.pick_start_level(all, 1)).is_equal(1)
	assert_int(PlayableTempo.pick_start_level(PackedInt32Array([0]), 3)).is_equal(0)
	assert_int(PlayableTempo.faster_than(2, all, 3)).is_equal(3)
	assert_int(PlayableTempo.faster_than(3, all, 3)).is_equal(3)
	assert_int(PlayableTempo.faster_than(0, all, 3)).is_equal(2)


func test_speed_is_not_sim_state_tick_count_independent_of_speed() -> void:
	var a := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade as SimFacadeImpl
	var b := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade as SimFacadeImpl
	a.set_speed(SimFacade.SPEED_NORMAL)
	PlayableTempo.apply_start_speed(b)
	assert_int(b.speed()).is_equal(SimFacade.SPEED_FAST)
	a.advance(40)
	b.advance(40)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_int(a.current_tick()).is_equal(b.current_tick())


# --- İpucu ---

func test_road_event_shows_hint_with_real_actions() -> void:
	var s := _scene()
	var hint: PlayableSpeedHint = s["hint"]
	assert_bool(hint.visible).is_false()
	_send(s, _road_event())
	assert_bool(hint.visible).is_true()
	assert_str(hint.hint_text()).is_equal("Zamanı hızlandırarak sonucu izle")
	assert_str(hint.close_button().text).is_equal("Kapat")
	assert_str(hint.faster_button().text).is_equal("Hızlandır")
	# Konum: harita dikdörtgeni içinde; bildirim şeridi bölgesiyle (sol %45) çakışmaz.
	var hud: HudRoot = s["hud"]
	assert_bool(hud.free_map_rect().encloses(Rect2(hint.position, hint.size))).is_true()
	assert_bool(hint.position.x >= hud.layout.notifications.end.x).is_true()


func test_zoning_applied_event_shows_hint() -> void:
	var s := _scene()
	_send(s, _zoning_event())
	assert_bool((s["hint"] as PlayableSpeedHint).visible).is_true()


func test_unrelated_event_does_not_show_hint() -> void:
	var s := _scene()
	var e := SimEvent.new()
	e.kind = SimEvent.KIND_PARCEL_CHANGED
	e.message_key = &"event.construction.started"
	_send(s, e)
	assert_bool((s["hint"] as PlayableSpeedHint).visible).is_false()


func test_faster_button_raises_speed_and_dismisses_permanently() -> void:
	var s := _scene()
	var hint: PlayableSpeedHint = s["hint"]
	var f: SimFacade = s["facade"]
	_send(s, _road_event())
	hint.faster_button().pressed.emit()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FASTEST)
	assert_bool(hint.visible).is_false()
	assert_bool((s["prefs"] as PlayableHintPrefs).is_dismissed(PlayableSpeedHint.HINT_ID)).is_true()


func test_close_is_permanent_across_sessions() -> void:
	var s := _scene()
	var hint: PlayableSpeedHint = s["hint"]
	_send(s, _road_event())
	hint.close_button().pressed.emit()
	assert_bool(hint.visible).is_false()
	# Aynı oturumda ikinci tetik: çıkmaz.
	_send(s, _zoning_event())
	assert_bool(hint.visible).is_false()
	# Yeni oturum (yeni sahne, aynı tercih dosyası): çıkmaz.
	var s2 := _scene()
	_send(s2, _road_event())
	assert_bool((s2["hint"] as PlayableSpeedHint).visible).is_false()


func test_hint_shows_at_most_once_per_session_even_without_close() -> void:
	var s := _scene()
	var hint: PlayableSpeedHint = s["hint"]
	_send(s, _road_event())
	hint._process(PlayableSpeedHint.HIDE_AFTER_S + 1.0)  # kendiliğinden gizlenir (kalıcı kapatma DEĞİL)
	assert_bool(hint.visible).is_false()
	assert_bool(hint.is_dismissed()).is_false()
	_send(s, _zoning_event())
	assert_bool(hint.visible).is_false()


func test_no_hint_when_already_at_top_speed() -> void:
	var s := _scene()
	var f: SimFacade = s["facade"]
	f.set_speed(SimFacade.SPEED_FASTEST)
	_send(s, _road_event())
	assert_bool((s["hint"] as PlayableSpeedHint).visible).is_false()


func test_player_changing_speed_dismisses_visible_hint() -> void:
	var s := _scene()
	var hint: PlayableSpeedHint = s["hint"]
	_send(s, _road_event())
	(s["hud"] as HudRoot).speed_changed.emit(SimFacade.SPEED_NORMAL)
	assert_bool(hint.visible).is_false()
	assert_bool(hint.is_dismissed()).is_true()


func test_paused_shows_resume_label() -> void:
	var s := _scene()
	var f: SimFacade = s["facade"]
	f.set_speed(SimFacade.SPEED_PAUSED)
	_send(s, _road_event())
	var hint: PlayableSpeedHint = s["hint"]
	assert_bool(hint.visible).is_true()
	assert_str(hint.faster_button().text).is_equal("Sürdür")
	hint.faster_button().pressed.emit()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FAST)


# --- Gün sayacı ---

func test_day_counter_stays_visible_while_hint_shows() -> void:
	var s := _scene()
	var hud: HudRoot = s["hud"]
	_send(s, _road_event())
	(s["facade"] as SimFacadeImpl).advance(5)
	hud.refresh()
	assert_str(hud.top_bar.date_text()).is_equal("1. yıl, 6. gün")
	assert_bool(hud.top_bar.is_visible_in_tree()).is_true()
