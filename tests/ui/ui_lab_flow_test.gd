extends GdUnitTestSuite
## T-019 ölçüt 4 · ui_lab uçtan uca mini imar akışı, MockSimFacade ile:
## parsel seç -> arazi kullanımı -> validate_command (gerekçeli ret ekranda, gönder devre dışı + gerekçe)
## -> geçerli kullanım -> gönder -> olay akışında sonuç -> "Nedenini gör" gerekçe paneli.
## Olumsuz: reddedilen öneri GÖNDERİLEMEZ; harita boşluğuna dokunmak seçimi kaldırır.

const LAB_SCENE := "res://scenes/dev/ui_lab.tscn"


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _lab() -> Node:
	var lab: Node = auto_free((load(LAB_SCENE) as PackedScene).instantiate())
	add_child(lab)
	return lab


func test_lab_binds_a_mock_facade_and_shows_mock_marks() -> void:
	var lab := _lab()
	await await_idle_frame()
	assert_bool(lab.facade is MockSimFacade).is_true()
	assert_bool(lab.facade.is_mock()).is_true()
	assert_bool(lab.hud.banner.visible).is_true()


func test_validate_rejection_is_shown_with_reason_and_blocks_sending() -> void:
	var lab := _lab()
	await await_idle_frame()
	lab.select_parcel(1)
	lab.open_zoning()
	var flow: ZoningFlowPanel = lab.zoning_flow()
	flow.choose_use(&"zone.industrial")  # mock sim bu kullanımı tanımıyor
	assert_bool(flow.last_validation.is_rejected()).is_true()
	assert_that(flow.last_validation.reason_key).is_equal(CommandResult.REJECT_INVALID_VALUE)
	assert_str(flow.verdict_text()).contains("arazi kullanımı")
	assert_bool(flow.send_button().is_enabled()).is_false()
	assert_str(flow.send_button().reason_text()).is_not_empty()
	flow.send()
	assert_object(flow.last_submit).is_null()  # reddedilen öneri gönderilmedi
	assert_int(lab.facade.last_event_seq()).is_equal(0)


func test_valid_proposal_runs_end_to_end_to_the_investor_reason() -> void:
	var lab := _lab()
	await await_idle_frame()
	lab.select_parcel(1)
	lab.open_zoning()
	var flow: ZoningFlowPanel = lab.zoning_flow()
	flow.choose_use(&"zone.mixed")
	assert_bool(flow.last_validation.is_rejected()).is_false()
	assert_str(flow.verdict_text()).is_equal("Öneri geçerli; gönderilebilir")
	assert_bool(flow.send_button().is_enabled()).is_true()
	flow.send()
	assert_that(flow.last_submit.status).is_equal(CommandResult.STATUS_QUEUED)
	assert_str(flow.queued_text()).contains("sıraya alındı")
	lab.facade.advance(6)
	lab.hud.poll()
	assert_bool(lab.hud.strip.visible).is_true()
	assert_bool(Array(lab.hud.strip.row_texts()).has("Yatırımcı vazgeçti")).is_true()
	for b in UiTestSupport.visible_buttons(lab.hud.strip):
		if b.text == UiText.t(&"alert.open_reason"):
			b.pressed.emit()
	assert_that(lab.hud.panel_id()).is_equal(&"reason")
	var panel := _find_panel(lab.hud.panel)
	assert_object(panel).is_not_null()
	var joined := " ".join(panel.texts())
	assert_str(joined).contains("Yatırımcı vazgeçti")
	assert_str(joined).contains("Altyapı kapasitesi")
	assert_str(joined).contains("eşiğe ulaşılmadı")
	assert_str(joined).contains("MOCK")


func test_map_tap_selects_nearest_parcel_and_empty_tap_clears() -> void:
	var lab := _lab()
	await await_idle_frame()
	var marker: Rect2 = lab.map.marker_rect(1)
	assert_float(marker.size.x).is_greater(0.0)
	lab.hud.input.select_requested.emit(marker.get_center())
	assert_int(lab.state()["selected"]).is_equal(1)
	assert_that(lab.hud.panel_id()).is_equal(&"inspector")
	lab.hud.input.select_requested.emit(Vector2(-500, -500))
	assert_int(lab.state()["selected"]).is_equal(0)
	assert_bool(lab.hud.is_panel_open()).is_false()


func test_zoning_without_parcel_asks_for_selection() -> void:
	var lab := _lab()
	await await_idle_frame()
	lab.open_zoning()
	var flow: ZoningFlowPanel = lab.zoning_flow()
	assert_object(flow.use_button(&"zone.mixed")).is_null()  # parsel yokken seçenek yok (ölü düğme yok)


func _find_panel(node: Node) -> ReasonPanel:
	if node is ReasonPanel:
		return node
	for child in node.get_children():
		var found := _find_panel(child)
		if found != null:
			return found
	return null
