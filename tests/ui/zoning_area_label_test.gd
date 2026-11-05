extends GdUnitTestSuite
## B-031 / B-032 · Sanat direktörü düzeltmeleri (M2): imar panelinde ham parsel numarası yerine anlamlı etiket
## (sim `area_m2`, `region_code`; yol verisi sözleşmede yok -> uydurulmaz) ve seçili parsellerin haritada vurgusu
## (HudRoot sinyali -> ParcelAreaHighlight; yalnız görünüm). Başsız: gerçek ekran görüntüsü DEĞİL.

const FIXTURE := "mock_scenario_investment_declined"


class AreaFacade extends MockSimFacade:
	var views: Dictionary = {}

	func parcel_views(ids: PackedInt64Array) -> Array[ParcelView]:
		var out: Array[ParcelView] = []
		for id in ids:
			if views.has(id):
				out.append(views[id])
		return out


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _view(id: int, area: int, region: StringName) -> ParcelView:
	var v := ParcelView.new()
	v.id = id
	v.area_m2 = area
	v.region_code = region
	return v


func _facade(n: int) -> AreaFacade:
	var f := AreaFacade.new(MockScenario.load_file(FlowTestSupport.FIXTURES + FIXTURE + ".json"))
	for i in range(1, n + 1):
		f.views[19800 + i] = _view(19800 + i, 100 + i, &"R%d" % (1 + i % 2))
	return f


func _panel(f: AreaFacade, n: int) -> ZoningFlowPanel:
	var ctx := UiContext.for_profile_name(&"touch")
	var model := ZoningFlowModel.create(f)
	for i in range(1, n + 1):
		model.add_parcel(19800 + i)
	var p := ZoningFlowPanel.create(ctx, f, model)
	add_child(p)
	return p


func test_row_head_uses_sim_area_and_region_never_the_raw_id() -> void:
	var s := ZoningParcelText.row_head(3, _view(19837, 420, &"R3"))
	assert_str(s).is_equal("3. parsel · 420 m² · Bölge R3")
	assert_str(s).not_contains("19837")
	# Bilinmeyen alan sıfır gösterilmez; görünüm yoksa yalnız sıra.
	assert_str(ZoningParcelText.row_head(1, _view(1, 0, &""))).is_equal("1. parsel")
	assert_str(ZoningParcelText.row_head(2, null)).is_equal("2. parsel")


func test_summary_totals_area_and_names_regions() -> void:
	var views: Array[ParcelView] = [_view(1, 100, &"R2"), _view(2, 250, &"R1"), _view(3, 50, &"R2")]
	assert_str(ZoningParcelText.summary(3, views)).is_equal("3 parsel · toplam 400 m² · Bölge R1, R2")
	var many: Array[ParcelView] = []
	for i in 5:
		many.append(_view(i + 1, 10, StringName("R%d" % i)))
	assert_str(ZoningParcelText.summary(5, many)).contains("5 bölge")


func test_small_area_lists_labelled_rows_without_raw_ids() -> void:
	var p := _panel(_facade(2), 2)
	var t := p.joined_text()
	assert_str(t).contains("1. parsel · 101 m² · Bölge R2")
	assert_str(t).contains("2. parsel · 102 m² · Bölge R1")
	assert_str(t).not_contains("19801")
	assert_int(p.named_buttons("area_remove_").size()).is_equal(2)


func test_fifteen_parcels_fold_into_one_summary_and_expand_on_demand() -> void:
	var p := _panel(_facade(15), 15)
	assert_str(p.joined_text()).contains("15 parsel · toplam 1.620 m² · Bölge R1, R2")
	assert_str(p.joined_text()).not_contains("19801")
	assert_int(p.named_buttons("area_remove_").size()).is_equal(0)
	var toggle := p.named_buttons("area_list_toggle")[0]
	assert_float(toggle.get_combined_minimum_size().y).is_greater_equal(44.0)
	toggle.pressed.emit()
	assert_int(p.named_buttons("area_remove_").size()).is_equal(15)
	assert_str(p.joined_text()).contains("15. parsel · 115 m²")
	assert_str(p.joined_text()).not_contains("19801")
	# Kullanım seçimi ve gönder ilk ekranda kalır (liste katlıyken de).
	p.named_buttons("area_list_toggle")[0].pressed.emit()
	assert_object(p.use_button(&"zone.mixed")).is_not_null()


func test_hud_highlight_follows_zoning_area_and_clears_on_close_or_other_panel() -> void:
	var f := _facade(3)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.size = Vector2(1600, 900)
	hud.refresh()
	auto_free(hud)
	var d := DecisionPanels.attach(hud, f)
	var seen: Array = []
	hud.map_highlight_changed.connect(func(ids: PackedInt64Array) -> void: seen.append(Array(ids)))
	d.open_zoning(PackedInt64Array([19801, 19802]))
	assert_array(Array(hud.map_highlight())).is_equal([19801, 19802])
	assert_bool(d.add_zoning_parcel(19803)).is_true()
	assert_array(Array(hud.map_highlight())).is_equal([19801, 19802, 19803])
	d.zoning_panel().refresh()  # aynı alan: yeni sinyal yok
	assert_int(seen.size()).is_equal(2)
	hud.open_panel(&"council", &"council.title", func(_c: UiContext) -> Control: return Control.new())
	assert_int(hud.map_highlight().size()).is_equal(0)
	d.open_zoning(PackedInt64Array([19801]))
	assert_int(hud.map_highlight().size()).is_equal(1)
	hud.close_panel_hard()
	assert_int(hud.map_highlight().size()).is_equal(0)
	# Başka panelin kimliğiyle gelen istek yok sayılır.
	hud.set_map_highlight(&"zoning", PackedInt64Array([5]))
	assert_int(hud.map_highlight().size()).is_equal(0)


func _parcel(pid: int, cx: float) -> WorldParcel:
	var p := WorldParcel.new()
	p.id = pid
	p.outline = PackedVector2Array([Vector2(cx - 10, 0), Vector2(cx + 10, 0), Vector2(cx + 10, 20),
			Vector2(cx - 10, 20)])
	p.centroid = Vector2(cx, 10.0)
	p.area = 400.0
	return p


func test_area_highlight_marks_exactly_the_listed_parcels_and_reads_only_world_data() -> void:
	var h: ParcelAreaHighlight = auto_free(ParcelAreaHighlight.new())
	add_child(h)
	h.ground_height = func(_x: float, _z: float) -> float: return 0.0
	for i in 5:
		h.parcels[100 + i] = _parcel(100 + i, 30.0 * i)
	h.set_band(&"street")
	h.show_parcels(PackedInt64Array([100, 102, 104, 999]))  # 999 dünyada yok: atlanır
	assert_int(h.marked_count()).is_equal(3)
	assert_array(Array(h.highlighted_ids())).is_equal([100, 102, 104])
	h.show_parcels(PackedInt64Array([101]))
	assert_int(h.marked_count()).is_equal(1)
	assert_array(Array(h.highlighted_ids())).is_equal([101])
	h.show_parcels(PackedInt64Array())
	assert_int(h.marked_count()).is_equal(0)
	# Metro bandında parsel işareti yok (ring kuralı).
	h.set_band(&"metro")
	h.show_parcels(PackedInt64Array([100]))
	assert_int(h.marked_count()).is_equal(0)


func test_area_highlight_follows_the_hud_signal() -> void:
	var f := _facade(1)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.size = Vector2(1600, 900)
	hud.refresh()
	auto_free(hud)
	var parent: Node3D = auto_free(Node3D.new())
	add_child(parent)
	var net := WorldNetwork.new()
	net.parcels[19801] = _parcel(19801, 0.0)
	var h := ParcelAreaHighlight.attach(hud, null, net, parent, func(_x: float, _z: float) -> float: return 0.0)
	h.set_band(&"street")
	var d := DecisionPanels.attach(hud, f)
	d.open_zoning(PackedInt64Array([19801]))
	assert_array(Array(h.highlighted_ids())).is_equal([19801])
	hud.close_panel_hard()
	assert_int(h.marked_count()).is_equal(0)
