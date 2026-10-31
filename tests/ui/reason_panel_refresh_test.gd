extends GdUnitTestSuite
## Demo kare takılması (2026-10-31): ReasonPanel.refresh() her sim tick'inde tüm liste düğümlerini yeniden kuruyordu
## (35 satırlı liste ~34 ms/tick). Davranış sözleşmesi: liste görünümünde KAYIT KÜMESİ değişmediyse düğümler
## yeniden kurulmaz; yeni kayıt gelince liste gerçekten güncellenir; ayrıntı görünümü eskisi gibi yeniden okunur.

const SCENARIO := "mock_scenario_investment_declined"


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _panel(facade: SimFacade) -> ReasonPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440, 1200)
	add_child(holder)
	auto_free(holder)
	var p := ReasonPanel.create(ctx, facade)
	holder.add_child(p)
	p.size = Vector2(440, 1200)
	return p


func _facade() -> UiLabReasonFacade:
	return UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + SCENARIO + ".json", UiLabReasonFacade.chain_records())


func _row_ids(p: ReasonPanel) -> Array[int]:
	var out: Array[int] = []
	for b in p.named_buttons(ReasonPanel.NAME_ROW):
		out.append(b.get_instance_id())
	return out


func test_list_refresh_with_same_records_keeps_nodes() -> void:
	var f := _facade()
	var p := _panel(f)
	p.show_subject(&"parcel.1")
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_LIST)
	var before := _row_ids(p)
	assert_int(before.size()).is_greater_equal(2)
	p.refresh()
	p.refresh()
	assert_array(_row_ids(p)).is_equal(before)  # aynı düğümler: yeniden kurulmadı


func test_list_refresh_rebuilds_when_a_new_record_arrives() -> void:
	var f := _facade()
	var p := _panel(f)
	p.show_subject(&"parcel.1")
	var before := _row_ids(p)
	var extra := UiLabReasonFacade.chain_records()[0]
	extra.id = 99
	extra.tick = 500
	f.records.append(extra)
	p.refresh()
	var after := _row_ids(p)
	assert_int(after.size()).is_equal(before.size() + 1)  # yeni kayıt görünür


func test_detail_refresh_still_rerenders() -> void:
	var f := _facade()
	var p := _panel(f)
	p.show_record(1)
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_DETAIL)
	var first_child := p.find_roles(ReasonPanel.NAME_FACTOR)
	assert_int(first_child.size()).is_greater(0)
	var ids: Array[int] = []
	for c in first_child:
		ids.append(c.get_instance_id())
	p.refresh()
	var again := p.find_roles(ReasonPanel.NAME_FACTOR)
	assert_int(again.size()).is_equal(ids.size())
	for c in again:
		assert_bool(ids.has(c.get_instance_id())).is_false()  # ayrıntı yeniden kuruldu (davranış değişmedi)
