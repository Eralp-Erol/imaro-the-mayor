extends GdUnitTestSuite
## B-015 UI ucu (SIM-12, CAN-04, D-014 §1) · Yıkılan kamulaştırmalı yolun şeridine yeniden çizim: sim teklifi
## `taken_parcels = 0` ile gelir. Panel "Bu yol yapılamaz: ... kamulaştırma henüz yok" DİYEMEZ ve "0 parsel
## kamulaştırılacak / 0 hane" da; dürüst ifade: "alınacak arsa yok", yıkım uyarısı yok, tek ileri adım + onay.
## Sayı YALNIZ sim args'ından. `undo_note` (B-013 / Q-030) bu akışta gösterilmez ve metni değişmedi.
## Gerçek oyun karesi: `tools/godot/zero_parcel_probe.gd` (pencereli).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const START := Vector2(-450.0, 210.0)
const END := Vector2(-450.0, 110.0)
const CROSSES := &"public_work.reject.crosses_parcels"


## Sim'in B-015 sonrası davranışı: kamulaştırmasız sorgu `crosses_parcels` + `taken_parcels: 0`, `expropriate: true`
## sorgusu geçerli ve alınan sıfır.
class ZeroStripFacade extends MockSimFacade:
	func validate_command(command: SimCommand) -> CommandResult:
		var args := {"taken_parcels": 0, "taken_built_parcels": 0, "displaced_households": 0, "length_m": 100,
				"units_total": 4}
		if bool(command.params.get("expropriate", false)):
			var ok := CommandResult.accepted(command, CommandResult.STATUS_VALID, SimContract.NO_ID, 0, &"test")
			ok.args = SimContract.to_args(args)
			return ok
		return CommandResult.rejected(command, CROSSES, args, 0, &"test")


var _facade: SimFacade
var _net: WorldNetwork
var _tool: RoadDrawTool


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_facade = ZeroStripFacade.new()
	_net = P.network()
	_tool = RoadDrawTool.create(_net, _facade)
	_tool.activate()
	_tool.start = START
	_tool.end = END
	_tool.step = RoadDrawTool.Step.REVIEW
	_tool.refresh_if_graph_changed()


func after_test() -> void:
	UiText.reset()


func _panel(profile: StringName = &"desktop", window: Vector2 = Vector2(440.0, 1400.0)) -> RoadDrawPanel:
	var ctx := UiContext.for_profile_name(profile)
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = window
	add_child(holder)
	auto_free(holder)
	var panel := RoadDrawPanel.create(ctx, _facade, _tool)
	holder.add_child(panel)
	panel.size = window
	return panel


func test_zero_parcel_proposal_is_an_offer_not_a_dead_end() -> void:
	assert_str(String(_tool.verdict.reason_key)).is_equal(CROSSES)
	assert_bool(_tool.offer().is_empty()).is_false()
	assert_bool(ExpropriationText.is_empty_strip(_tool.verdict.args)).is_true()
	assert_bool(ExpropriationText.is_offer(CROSSES, _tool.verdict.args)).is_true()
	# Anahtar hiç yoksa (kamulaştırma kapalı) teklif YOK ve eski metin kalır.
	assert_bool(ExpropriationText.is_empty_strip({})).is_false()
	assert_bool(ExpropriationText.is_offer(CROSSES, {})).is_false()


func test_the_card_says_nothing_is_taken_and_never_claims_parcels_or_a_missing_feature() -> void:
	var text := _panel().joined_text()
	assert_str(text).contains(UiText.t(&"expropriation.empty_title"))
	assert_str(text).contains(UiText.t(&"expropriation.empty_body"))
	for forbidden in ["yapılamaz", "henüz yok", "0 parsel", "0 hane", "0 bina", "Kamulaştırarak", "yıkılacak",
			"yerinden edilecek", "boş arsa alınacak", "tepki"]:
		assert_bool(text.contains(forbidden)).override_failure_message("yasak ifade: %s" % forbidden).is_false()
	assert_str(text).not_contains(UiText.t(&"expropriation.undo_note"))
	for money in ["₺", "TL", "lira"]:
		assert_bool(text.contains(money)).is_false()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_one_forward_button_with_plain_label_then_a_plain_confirm_and_no_demolition_wording() -> void:
	var panel := _panel()
	assert_object(panel.accept_button()).is_not_null()
	assert_str(panel.accept_button().text).is_equal(UiText.t(&"expropriation.empty_accept"))
	assert_object(panel.confirm_button()).is_null()
	panel.accept_button().pressed.emit()
	assert_bool(_tool.is_valid()).is_true()
	assert_bool(_tool.demolishes()).is_false()
	assert_bool(_tool.can_confirm()).is_true()
	assert_object(panel.confirm_button()).is_not_null()
	assert_str(panel.confirm_button().text).is_equal(UiText.t(&"road.confirm"))
	assert_bool(panel.confirm_button().disabled).is_false()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"expropriation.empty_valid"))
	assert_str(text).not_contains(UiText.t(&"expropriation.confirm"))   # "Yıkımı onayla" yok
	assert_str(text).not_contains(UiText.t(&"expropriation.valid_title"))
	assert_str(text).not_contains(UiText.t(&"expropriation.undo_note"))
	assert_object(panel.back_button()).is_null()   # "Kamulaştırmaktan vazgeç" bu akışta yanıltıcı; İptal var


func test_confirming_sends_the_expropriate_flag_so_the_sim_builds_the_pooled_plain_road() -> void:
	var panel := _panel()
	panel.accept_button().pressed.emit()
	assert_bool(_tool.expropriate).is_true()
	assert_bool(bool(_tool._command().params["expropriate"])).is_true()


func test_reject_reason_for_the_zero_offer_is_the_honest_line() -> void:
	var text := UiText.reject_reason(CROSSES, {"taken_parcels": 0})
	assert_str(text).is_equal(UiText.t(&"public_work.reject.crosses_parcels_empty"))
	assert_str(text).not_contains("henüz yok")
	assert_str(UiText.reject_reason(CROSSES, {})).contains("kamulaştırma henüz yok")   # kapalıyken eski metin


func test_touch_targets_are_at_least_44_and_spaced_8() -> void:
	var panel := _panel(&"touch", Vector2(520.0, 1200.0))
	assert_float(panel.accept_button().get_combined_minimum_size().y).is_greater_equal(44.0)
	panel.accept_button().pressed.emit()
	assert_float(panel.confirm_button().get_combined_minimum_size().y).is_greater_equal(44.0)
	var cancel := panel.find_child("road_cancel", true, false) as Button
	if cancel != null:
		assert_float(cancel.get_combined_minimum_size().y).is_greater_equal(44.0)
