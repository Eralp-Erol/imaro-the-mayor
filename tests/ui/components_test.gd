extends GdUnitTestSuite
## T-019 ölçüt 3/6 · Durum bileşenleri: StateView (yükleme/boş/hata/kurulmamış/devre dışı),
## ActionButton (gerekçesiz ölü düğme yok), PanelShell (sabit panel dolaylı kapanmaz),
## MOCK rozet/banner (facade bayrağı).
## Olumsuz: gerekçesiz devre dışı, sabit panelin dolaylı kapanması, MOCK olmayan facade'de işaretin
## kaybolması.

var _ctx: UiContext


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_ctx = UiContext.for_profile_name(&"desktop")


func after_test() -> void:
	UiText.reset()


func _themed(node: Control) -> Control:
	node.theme = UiTheme.build(_ctx)
	add_child(node)
	return auto_free(node)


# --- StateView ---

func test_state_view_each_state_shows_honest_nonempty_text() -> void:
	var v := _themed(StateView.create(_ctx)) as StateView
	v.loading_delay_s = 0.0
	v.show_loading()
	assert_str(v.visible_text()).is_equal("Yükleniyor")
	v.show_loading(40)
	assert_str(v.visible_text()).is_equal("Yükleniyor — %40")
	v.show_empty(&"state.empty.no_events")
	assert_str(v.visible_text()).is_equal("Henüz olay yok")
	v.show_error("Simülasyondan veri alınamadı", true)
	assert_str(v.visible_text()).contains("Bir sorun oluştu")
	assert_bool(v.retry_visible()).is_true()
	v.show_not_built(&"council.not_built")
	assert_str(v.visible_text()).is_equal("Meclis sistemi henüz kurulmadı")
	v.show_disabled("Önce seçim yapın")
	assert_str(v.visible_text()).is_equal("Kullanılamıyor: Önce seçim yapın")
	for state in [StateView.State.EMPTY, StateView.State.ERROR]:
		assert_bool(state != StateView.State.NORMAL).is_true()


func test_state_view_loading_is_hidden_until_delay_elapses() -> void:
	var v := _themed(StateView.create(_ctx)) as StateView
	v.loading_delay_s = 0.3
	v.show_loading()
	assert_str(v.visible_text()).is_empty()
	v._process(0.1)
	assert_str(v.visible_text()).is_empty()
	v._process(0.25)
	assert_str(v.visible_text()).is_equal("Yükleniyor")


func test_state_view_normal_shows_content_and_other_states_hide_it() -> void:
	var v := _themed(StateView.create(_ctx)) as StateView
	v.set_content(Label.new())
	v.show_normal()
	assert_bool(v.content_visible()).is_true()
	v.show_not_built()
	assert_bool(v.content_visible()).is_false()
	v.show_disabled("")
	assert_str(v.visible_text()).contains("Bilinmiyor")


func test_state_view_error_retry_signal() -> void:
	var v := _themed(StateView.create(_ctx)) as StateView
	var hits := [0]
	v.retry_requested.connect(func() -> void: hits[0] += 1)
	v.show_error("x", true)
	v._retry.pressed.emit()
	assert_int(hits[0]).is_equal(1)
	v.show_error("x", false)
	assert_bool(v.retry_visible()).is_false()


# --- ActionButton ---

func test_disabled_action_button_always_explains_why() -> void:
	var a := _themed(ActionButton.create(_ctx, "Gönder")) as ActionButton
	a.set_enabled(false, "Bütçe yetmiyor")
	assert_bool(a.is_enabled()).is_false()
	assert_str(a.reason_text()).is_equal("Kullanılamıyor: Bütçe yetmiyor")
	a.set_enabled(false)
	assert_str(a.reason_text()).contains("Bilinmiyor")
	a.set_enabled(true)
	assert_str(a.reason_text()).is_empty()


func test_action_button_pressed_signal_only_when_enabled() -> void:
	var a := _themed(ActionButton.create(_ctx, "Gönder")) as ActionButton
	var hits := [0]
	a.pressed.connect(func() -> void: hits[0] += 1)
	a.button.pressed.emit()
	assert_int(hits[0]).is_equal(1)


# --- PanelShell ---

func test_panel_shell_pinned_panel_survives_soft_close_but_not_hard_close() -> void:
	var p := _themed(PanelShell.create(_ctx)) as PanelShell
	var closes := [0]
	p.closed.connect(func() -> void: closes[0] += 1)
	p.pin_button().button_pressed = true
	assert_bool(p.pinned).is_true()
	assert_bool(p.request_soft_close()).is_false()
	assert_int(closes[0]).is_equal(0)
	p.close_button().pressed.emit()
	assert_int(closes[0]).is_equal(1)


func test_panel_shell_unpinned_soft_close_works_and_labels_are_text() -> void:
	var p := _themed(PanelShell.create(_ctx)) as PanelShell
	assert_str(p.close_button().text).is_equal("Kapat")
	assert_str(p.pin_button().text).is_equal("Sabitle")
	assert_bool(p.request_soft_close()).is_true()
	p.pin_button().button_pressed = true
	assert_str(p.pin_button().text).is_equal("Sabitlemeyi kaldır")


func test_panel_shell_accepts_pluggable_content() -> void:
	var p := _themed(PanelShell.create(_ctx)) as PanelShell
	var content := Label.new()
	content.text = "içerik"
	p.set_content(content)
	assert_bool(p.state_view.content_visible()).is_true()
	assert_bool(content.is_inside_tree()).is_true()


# --- MOCK işaretleri ---

func test_mock_badge_and_banner_follow_facade_flag_not_code() -> void:
	var badge := _themed(MockBadge.create()) as MockBadge
	var banner := _themed(MockBanner.create()) as MockBanner
	badge.apply_facade(UiTestSupport.mock())
	banner.apply_facade(UiTestSupport.mock())
	assert_bool(badge.visible).is_true()
	assert_bool(banner.visible).is_true()
	badge.apply_facade(UiTestSupport.non_mock())
	banner.apply_facade(UiTestSupport.non_mock())
	assert_bool(badge.visible).is_false()
	assert_bool(banner.visible).is_false()
	badge.apply_facade(null)
	assert_bool(badge.visible).is_false()
