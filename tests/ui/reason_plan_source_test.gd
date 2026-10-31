extends GdUnitTestSuite
## T-043B ölçüt 5 (UI yarısı, SIM-12) · Gerekçe zinciri okunur: bir etkenin `source_ref`i (`command.N`) parselin
## imar planı komutuna çözülüyorsa "Kaynak: oyuncunun imar planı, komut <gün>" (komut olayı saklıysa) ya da
## "... yürürlük <gün>" (saklı değilse, planın yürürlük günü) yazar. Plan komutu değilse genel "Kaynak: Komut N"
## kalır (uydurma yok). Yol kaynağı mevcut `reason.source_road` yolundadır (road_work_reason_test).

const COMMAND := &"command.7"

## Plan durumu ve komut olayı dışarıdan verilen sahte kaynak (sayılar SAHTE; yalnız UI çözümlemesini sınar).
class PlanFacade:
	extends UiLabReasonFacade
	var plan_command: StringName = &"command.7"
	var plan_due: int = 52
	var command_event_tick: int = -1

	func plan_state(parcel_id: int) -> PlanStateView:
		var v := PlanStateView.new()
		v.parcel_id = parcel_id
		v.state = PlanStateView.STATE_PLANNED
		v.source_ref = plan_command
		v.command_id = int(SimContract.parse_ref(plan_command)["id"])
		v.due_tick = plan_due
		return v

	func events_since(_after_seq: int, _max_count: int = 0) -> Array[SimEvent]:
		var out: Array[SimEvent] = []
		if command_event_tick >= 0:
			var e := SimEvent.new()
			e.kind = SimEvent.KIND_COMMAND_APPLIED
			e.tick = command_event_tick
			e.command_id = 7
			out.append(e)
		return out


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _facade(source: StringName) -> PlanFacade:
	var records := UiLabReasonFacade.chain_records()
	records[1].factors[2].source_ref = source
	var f := PlanFacade.new(MockScenario.load_file(UiTestSupport.FIXTURES + UiTestSupport.DECLINED + ".json"))
	f.records = records
	return f


func _joined(facade: SimFacade) -> String:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder: Control = auto_free(Control.new())
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	var p := ReasonPanel.create(ctx, facade)
	holder.add_child(p)
	p.size = holder.size
	p.show_record(2)
	return " | ".join(p.texts())


func test_plan_command_source_shows_plan_and_command_day() -> void:
	var f := _facade(COMMAND)
	f.command_event_tick = 40
	assert_str(_joined(f)).contains("Kaynak: oyuncunun imar planı, komut 1. yıl, 41. gün")


func test_plan_source_falls_back_to_enactment_day_when_command_event_not_retained() -> void:
	var f := _facade(COMMAND)
	assert_str(_joined(f)).contains("Kaynak: oyuncunun imar planı, yürürlük 1. yıl, 53. gün")


func test_command_that_is_not_the_parcels_plan_stays_generic() -> void:
	var f := _facade(&"command.9")
	f.command_event_tick = 40
	var text := _joined(f)
	assert_bool(text.contains("imar planı, komut")).is_false()
	assert_bool(text.contains("imar planı, yürürlük")).is_false()
	assert_str(text).contains("Kaynak: Komut 9")
