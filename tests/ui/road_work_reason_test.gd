extends GdUnitTestSuite
## T-042 adım 3 (SIM-12, D-008) · "Yol yapıldı" olay kartı ve yatırımcı gerekçesinde yol kaynağı: şeritteki olay
## "Yol ayrıntısı" düğmesi sunar -> ReasonPanel yol kaydını (sim `public_works()`) gösterir; onaylı parselin
## "Altyapı kapasitesi" etkeni oyuncu yoluna bağlanır ve bağlantı yol ayrıntısını açar. Yol geri alınınca dürüstçe
## "artık yok" denir; kaynaksız etken bağlantı taşımaz. Sentetik iki bölge dünyası (gerçek Ismeral değil).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const INFRA := &"reason.factor.infrastructure_capacity"
const WARMUP := 40
const AFTER := 70

var _facade: SimFacadeImpl
var _net: WorldNetwork


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	var run := P.setup(P.SEED)
	_facade = run["facade"]
	_net = run["net"]
	_facade.advance(WARMUP)


func after_test() -> void:
	UiText.reset()


func _holder(size: Vector2 = Vector2(440.0, 1400.0)) -> Control:
	var holder: Control = auto_free(Control.new())
	holder.theme = UiTheme.build(UiContext.for_profile_name(&"desktop"))
	holder.size = size
	add_child(holder)
	return holder


func _panel() -> ReasonPanel:
	var p := ReasonPanel.create(UiContext.for_profile_name(&"desktop"), _facade)
	var holder := _holder()
	holder.add_child(p)
	p.size = holder.size
	return p


func _build_road() -> SimEvent:
	var r := _facade.submit_command(P.road(P.spur_a_cm()))
	assert_str(String(r.status)).is_equal("queued")
	_facade.advance(AFTER)
	for e in _facade.events_since(0):
		if e.kind == SimEvent.KIND_PUBLIC_WORK_BUILT:
			return e
	return null


func _approved_reason() -> ReasonRecord:
	for v in _facade.parcel_views(_facade.parcel_ids(P.CODE_A)):
		if v.decision != &"approved":
			continue
		var found: ReasonRecord = null
		for r in _facade.reasons_for(v.ref()):
			if r.decision_key == &"decision.investor.develop":
				found = r
		if found != null:
			return found
	return null


func test_the_built_event_card_offers_the_road_detail_and_opens_the_real_work_record() -> void:
	var built := _build_road()
	assert_object(built).is_not_null()
	var strip := NotificationStrip.create(UiContext.for_profile_name(&"desktop"))
	_holder().add_child(strip)
	var seen: Array[SimEvent] = []
	strip.reason_requested.connect(func(e: SimEvent) -> void: seen.append(e))
	var events: Array[SimEvent] = [built]
	strip.push_events(events)
	await get_tree().process_frame
	var text := " | ".join(strip.row_texts())
	assert_str(text).contains("Yol yapıldı")
	assert_str(text).not_contains("event.road")
	var detail: Button = null
	for b in UiTestSupport.visible_buttons(strip):
		if b.text == UiText.t(&"alert.open_work"):
			detail = b
	assert_object(detail).override_failure_message("'Yol ayrıntısı' düğmesi yok").is_not_null()
	detail.pressed.emit()
	assert_int(seen.size()).is_equal(1)
	var panel := _panel()
	panel.show_event(seen[0])
	var shown := " | ".join(panel.texts())
	var work := _facade.public_works()[0]
	assert_str(shown).contains(UiText.t(&"reason.work_title"))
	assert_str(shown).contains(UiText.t(&"road.length", {"length": int(work.length_cm / 100)}))
	assert_str(shown).contains(UiText.t(&"public_work.cost.not_built"))
	assert_str(shown).not_contains("public_work.")
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_investor_reason_names_the_player_road_as_the_source_of_the_capacity_factor_and_links_to_it() -> void:
	_build_road()
	var reason := _approved_reason()
	assert_object(reason).override_failure_message("A bölgesinde onaylı yatırım yok").is_not_null()
	var panel := _panel()
	panel.show_record(reason.id)
	var shown := " | ".join(panel.texts())
	assert_str(shown).contains(UiText.t(INFRA))
	var work := _facade.public_works()[0]
	var source := UiText.t(&"reason.source_road", {"date": UiText.tick_date(work.tick),
			"length": int(work.length_cm / 100)})
	assert_str(shown).override_failure_message(shown).contains(source)
	var link: Button = null
	for b in panel.named_buttons(ReasonPanel.NAME_SUBJECT + "_src_"):
		if b.text == source:
			link = b
	assert_object(link).override_failure_message("yol bağlantısı düğmesi yok").is_not_null()
	link.pressed.emit()
	assert_str(" | ".join(panel.texts())).contains(UiText.t(&"reason.work_title"))
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_after_undo_the_work_record_is_honestly_gone_and_the_link_disappears() -> void:
	_build_road()
	var reason := _approved_reason()
	assert_object(reason).is_not_null()
	var cmd := _facade.public_works()[0].command_id
	assert_bool(_facade.submit_command(SimCommand.public_work_undo_last()).is_rejected()).is_false()
	_facade.advance(1)
	assert_array(_facade.public_works()).is_empty()
	var panel := _panel()
	panel.show_work(cmd)
	assert_str(" | ".join(panel.texts())).contains(UiText.t(&"reason.work_gone"))
	# Geçmiş karar kaydı durur; kaynak yol artık yok -> bağlantı yok, ham anahtar yok.
	panel.show_record(reason.id)
	var shown := " | ".join(panel.texts())
	assert_str(shown).not_contains("command.")
	assert_str(shown).not_contains("reason.source_road")
	assert_array(panel.named_buttons(ReasonPanel.NAME_SUBJECT + "_src_command")).is_empty()


func test_regions_without_the_road_carry_no_road_link() -> void:
	_build_road()
	var panel := _panel()
	for v in _facade.parcel_views(_facade.parcel_ids(P.CODE_B)):
		for r in _facade.reasons_for(v.ref()):
			if r.decision_key == &"decision.investor.develop":
				panel.show_record(r.id)
				assert_array(panel.named_buttons(ReasonPanel.NAME_SUBJECT + "_src_command")).is_empty()
				return
	fail("B bölgesinde yatırımcı gerekçesi bulunamadı")
