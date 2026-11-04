extends GdUnitTestSuite
## T-066 / D-018 · İmar akışında "boş belediye arazisini imara aç" girişi (ZoningFlowModel + ZoningFlowPanel).
## Sahte facade: gerçek MockSimFacade + belediye arazisi satırları; komut/önizleme argümanlarını kaydeder.
## Sim tarafının gerçek reddi tests/sim/public_works/municipal_land_*.gd ile sınanır; burada UI davranışı vardır.

const FIXTURE := "mock_scenario_investment_declined"


class LandFacade extends MockSimFacade:
	var lands: Array[MunicipalLandView] = []
	var limit: int = 0
	var preview_flags: Array[bool] = []
	var validated: Array[SimCommand] = []

	func municipal_lands() -> Array[MunicipalLandView]:
		return lands

	func plan_preview(parcel_ids: PackedInt64Array, land_use: StringName, _density: int = -1,
			_max_height_m: int = -1, municipal_reuse: bool = false) -> PlanPreviewView:
		var v := PlanPreviewView.new()
		v.provenance = provenance()
		v.land_use = land_use
		v.max_parcels = limit
		if not parcel_ids.is_empty():
			preview_flags.append(municipal_reuse)
		return v

	func validate_command(command: SimCommand) -> CommandResult:
		validated.append(command)
		if bool(command.params.get("municipal_reuse", false)) and (command.params["parcel_ids"] as PackedInt64Array).has(9):
			return CommandResult.rejected(command, CommandResult.REJECT_PRECONDITION,
					{"why": "municipal_land.road_still_standing", "ref": "parcel.9"}, 0, provenance())
		return super.validate_command(command)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _land(id: int, available: bool = true) -> MunicipalLandView:
	var v := MunicipalLandView.new()
	v.id = id
	v.available = available
	return v


func _facade(rows: Array[MunicipalLandView], limit: int = 0) -> LandFacade:
	var f := LandFacade.new(MockScenario.load_file(FlowTestSupport.FIXTURES + FIXTURE + ".json"))
	f.lands = rows
	f.limit = limit
	return f


func _panel(f: LandFacade) -> ZoningFlowPanel:
	var ctx := UiContext.for_profile_name(&"touch")
	var p := ZoningFlowPanel.create(ctx, f, ZoningFlowModel.create(f))
	add_child(p)
	return p


func test_button_visible_with_real_count_and_adds_ids_in_municipal_mode() -> void:
	var f := _facade([_land(3), _land(2), _land(7, false)])
	var p := _panel(f)
	var btns := p.named_buttons("municipal_open")
	assert_int(btns.size()).is_equal(1)
	assert_str(btns[0].text).contains("2 parsel")  # yalnız uygun satırlar sayılır
	assert_float(btns[0].get_combined_minimum_size().y).is_greater_equal(44.0)
	assert_bool(p.open_municipal_land()).is_true()
	assert_bool(p.model.municipal_mode).is_true()
	assert_array(Array(p.model.parcel_ids)).is_equal([2, 3])
	assert_int(p.named_buttons("municipal_open").size()).is_equal(0)
	assert_str(p.joined_text()).contains("Belediye bina yapmaz")


func test_ids_capped_by_sim_parcel_limit() -> void:
	var f := _facade([_land(1), _land(2), _land(3)], 2)
	var m := ZoningFlowModel.create(f)
	assert_bool(m.use_municipal_land()).is_true()
	assert_array(Array(m.parcel_ids)).is_equal([1, 2])


func test_command_and_preview_carry_municipal_reuse() -> void:
	var f := _facade([_land(1), _land(2)])
	var m := ZoningFlowModel.create(f)
	m.use_municipal_land()
	m.choose_use(&"zone.mixed")
	assert_bool(bool(m.command().params.get("municipal_reuse", false))).is_true()
	assert_bool(bool((f.validated.back() as SimCommand).params.get("municipal_reuse", false))).is_true()
	m.choose_density(-1)
	m.preview()
	assert_bool(f.preview_flags.back()).is_true()


func test_ordinary_command_has_no_municipal_flag() -> void:
	var f := _facade([_land(1)])
	var m := ZoningFlowModel.create(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.command().params.has("municipal_reuse")).is_false()
	m.preview()
	assert_bool(f.preview_flags.back()).is_false()


func test_button_hidden_when_no_available_land() -> void:
	assert_int(_panel(_facade([]) ).named_buttons("municipal_open").size()).is_equal(0)
	var p := _panel(_facade([_land(4, false)]))
	assert_int(p.named_buttons("municipal_open").size()).is_equal(0)
	assert_str(p.joined_text()).not_contains("belediye arazisini imara aç")
	assert_bool(p.model.use_municipal_land()).is_false()


func test_no_mixed_selection_in_either_direction() -> void:
	var f := _facade([_land(1), _land(2)])
	var m := ZoningFlowModel.create(f)
	m.use_municipal_land()
	assert_bool(m.add_parcel(5)).is_false()  # kipte sıradan parsel eklenemez
	assert_array(Array(m.parcel_ids)).is_equal([1, 2])
	var o := ZoningFlowModel.create(f)
	o.add_parcel(5)
	assert_bool(o.use_municipal_land()).is_false()  # sıradan parsel varken kip açılmaz
	assert_bool(o.municipal_mode).is_false()
	var p := _panel(f)
	p.add_parcel(5)
	assert_int(p.named_buttons("municipal_open").size()).is_equal(0)
	assert_str(p.joined_text()).contains("önce alanı temizleyin")


func test_clearing_area_resets_mode() -> void:
	var f := _facade([_land(1), _land(2)])
	var m := ZoningFlowModel.create(f)
	m.use_municipal_land()
	m.remove_parcel(1)
	assert_bool(m.municipal_mode).is_true()
	m.clear_area()
	assert_bool(m.municipal_mode).is_false()
	assert_bool(m.add_parcel(5)).is_true()
	var n := ZoningFlowModel.create(f)
	n.use_municipal_land()
	n.remove_parcel(1)
	n.remove_parcel(2)
	assert_bool(n.municipal_mode).is_false()


func test_rejection_reason_is_plain_turkish() -> void:
	var f := _facade([_land(9)])
	var m := ZoningFlowModel.create(f)
	m.use_municipal_land()
	m.choose_use(&"zone.mixed")
	assert_bool(m.last_validation.is_rejected()).is_true()
	assert_str(m.verdict_text()).contains("Yol hâlâ ayakta")
	for key in ["not_available", "road_still_standing", "plan_pending", "world_unavailable"]:
		assert_bool(UiText.has(StringName("municipal_land." + key))).is_true()


func _many(n: int, area: int = 100) -> Array[MunicipalLandView]:
	var rows: Array[MunicipalLandView] = []
	for i in range(1, n + 1):
		var v := _land(i)
		v.area_m2 = area
		rows.append(v)
	return rows


## B-023: 15 parsel tek özet satırı (sim area_m2 toplamı); liste varsayılan kapalı, kullanım/gönder satırları yerinde.
func test_municipal_mode_groups_parcels_into_one_summary_and_list_folds() -> void:
	var p := _panel(_facade(_many(15, 120)))
	p.open_municipal_land()
	assert_int(p.named_buttons("area_remove_").size()).is_equal(0)
	assert_str(p.joined_text()).contains("15 parsel · toplam alan 1.800 m²")
	var toggle := p.named_buttons("municipal_list_toggle")[0]
	assert_float(toggle.get_combined_minimum_size().y).is_greater_equal(44.0)
	toggle.pressed.emit()
	assert_int(p.named_buttons("area_remove_").size()).is_equal(15)
	# Açık listede satırlar "Yapılı parsel" değil "Boş belediye arazisi" der (gerçek pencere karesinde görülen hata).
	assert_str(p.joined_text()).contains("Boş belediye arazisi")
	assert_str(p.joined_text()).not_contains("Yapılı parsel")
	p.named_buttons("municipal_list_toggle")[0].pressed.emit()
	assert_int(p.named_buttons("area_remove_").size()).is_equal(0)
	assert_object(p.use_button(&"zone.mixed")).is_not_null()
	assert_object(p.send_button()).is_not_null()


## B-024: uzun düğme metni dar panelde sarılır; asgari genişlik panelden büyük değil.
func test_open_button_wraps_in_narrow_panel_sizes() -> void:
	for width in [361, 330, 280]:
		var p := _panel(_facade(_many(15)))
		p.custom_minimum_size.x = 0
		var b := p.named_buttons("municipal_open")[0]
		assert_int(b.autowrap_mode).is_equal(TextServer.AUTOWRAP_WORD_SMART)
		assert_float(b.get_combined_minimum_size().x).is_less(float(width))
		assert_float(b.get_combined_minimum_size().y).is_greater_equal(44.0)
		p.queue_free()
