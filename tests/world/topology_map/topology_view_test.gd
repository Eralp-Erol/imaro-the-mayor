extends GdUnitTestSuite
## T-028 ölçüt 2/3/5 · görünüm: her veri işaretinin etiketi var (sayılar veriyle eşit), damga var, etiketler çakışmaz,
## kuzey oku yukarı, ölçek çubuğu piksel<->metre, yer adı yalnız D2 "Orven". Raster üretimi atlanır (headless).

var _m: TopologyModel
var _view: TopologyMapView
var _labels: Array[Dictionary]


func before() -> void:
	_m = TopologyTestSupport.full_model()
	_view = TopologyMapView.new()
	_view.setup(_m, false)
	_labels = _view.labels()


func after() -> void:
	_view.free()


func _of_kind(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in _labels:
		if l["kind"] == kind:
			out.append(l)
	return out


func test_label_counts_equal_the_data() -> void:
	assert_int(_of_kind(&"region").size()).is_equal(_m.world.regions.size())
	assert_int(_of_kind(&"island").size()).is_equal(_m.world.islands.size())
	var ports := 0
	var industries := 0
	for s in _m.world.sites:
		ports += 1 if s.kind == &"port" else 0
		industries += 1 if s.kind == &"first_industry" else 0
	assert_int(_of_kind(&"port").size()).is_equal(ports)
	assert_int(_of_kind(&"industry").size()).is_equal(industries)
	assert_int(_of_kind(&"gulf").size()).is_equal(1)
	assert_int(_of_kind(&"open_sea").size()).is_equal(1)
	assert_int(_of_kind(&"mainland").size()).is_equal(1)
	assert_int(_of_kind(&"gap").size()).is_equal(1)


func test_stamp_title_north_and_scale_labels_exist() -> void:
	var stamps := _of_kind(&"stamp")
	assert_int(stamps.size()).is_equal(1)
	assert_str(stamps[0]["text"]).is_equal(TopologyModel.STAMP)
	assert_int(_of_kind(&"title").size()).is_equal(1)
	assert_int(_of_kind(&"north").size()).is_equal(1)
	assert_int(_of_kind(&"scale").size()).is_equal(1)


func test_only_d2_label_carries_a_name_and_island_labels_are_ids() -> void:
	for l in _of_kind(&"region"):
		var text: String = l["text"]
		if text.begins_with("D2"):
			assert_str(text).contains("Orven")
		else:
			assert_int(text.length()).is_equal(2)
	for l in _of_kind(&"island"):
		assert_bool((l["text"] as String).begins_with("I")).is_true()
		assert_int((l["text"] as String).length()).is_less_equal(3)


func test_map_labels_do_not_overlap_each_other() -> void:
	var rects: Array = []
	for l in _labels:
		if not [&"title", &"stamp", &"north", &"scale"].has(l["kind"]):
			rects.append(l["rect"])
	assert_int(rects.size()).is_greater(15)
	assert_int(TopologyLabelPlacer.count_overlaps(rects)).is_equal(0)
	for r: Rect2 in rects:
		assert_bool(TopologyMapView.MAP_RECT.encloses(r)).is_true()


func test_labels_do_not_hide_the_site_markers() -> void:
	for s in _m.sites:
		var p := _view.projection().to_screen(s.position)
		for l in _labels:
			if [&"title", &"stamp", &"north", &"scale"].has(l["kind"]):
				continue
			assert_bool((l["rect"] as Rect2).has_point(p)).override_failure_message("%s kapatıyor: %s" % [
					l["text"], s.id]).is_false()


func test_north_arrow_points_up_and_scale_bar_matches_meters() -> void:
	var proj := _view.projection()
	assert_vector(proj.north_on_screen()).is_equal_approx(Vector2(0.0, -1.0), Vector2(0.001, 0.001))
	var bar := proj.scale_bar(TopologyMapView.SCALE_MAX_PX)
	var a := proj.to_screen(Vector2(1000.0, 1000.0))
	var b := proj.to_screen(Vector2(1000.0 + float(bar["meters"]), 1000.0))
	assert_float(a.distance_to(b)).is_equal_approx(float(bar["pixels"]), 0.01)
	# veri sınırı ekranda harita dikdörtgenine oturur (40 km = tüm harita genişliği)
	assert_float(proj.screen_rect.size.x).is_equal_approx(_m.bounds.size.x * proj.px_per_m, 0.01)


func test_site_marker_position_projects_to_the_data_position() -> void:
	var proj := _view.projection()
	for s in _m.sites:
		assert_vector(proj.to_world(proj.to_screen(s.position))).is_equal_approx(s.position, Vector2(0.01, 0.01))


func test_negative_view_without_stamp_would_be_caught() -> void:
	# Olumsuz: damga etiketi listeden çıkarılırsa "tam bir damga" ölçütü kırmızı olur.
	var kept: Array[Dictionary] = []
	for l in _labels:
		if l["kind"] != &"stamp":
			kept.append(l)
	var stamps := 0
	for l in kept:
		stamps += 1 if l["kind"] == &"stamp" else 0
	assert_int(stamps).is_not_equal(1)


func test_district_sheet_has_one_labelled_panel_per_region_and_the_stamp() -> void:
	var sheet := TopologyDistrictSheet.new()
	sheet.setup(_m, [], false)
	var panels := 0
	var stamps := 0
	var titles := ""
	for l in sheet.labels():
		panels += 1 if l["kind"] == &"panel" else 0
		stamps += 1 if l["kind"] == &"stamp" else 0
		titles += String(l["text"]) + "|"
	assert_int(panels).is_equal(_m.regions.size())
	assert_int(stamps).is_equal(1)
	assert_str(titles).contains("D2 · Orven")
	for p in sheet.panels():
		assert_bool(_m.bounds.encloses(p["window"])).is_true()
		assert_float((p["window"] as Rect2).size.x).is_equal(TopologyDistrictSheet.WINDOW_M)
	var one := TopologyDistrictSheet.new()
	one.setup(_m, [&"D3"], false)
	assert_int(one.panels().size()).is_equal(1)
	sheet.free()
	one.free()


func test_table_page_lists_every_row_question_and_the_stamp() -> void:
	var page := TopologyTablePage.new()
	page.setup(_m)
	var kinds := {}
	for l in page.labels():
		kinds[l["kind"]] = int(kinds.get(l["kind"], 0)) + 1
	assert_int(kinds[&"stamp"]).is_equal(1)
	assert_int(kinds[&"row"]).is_equal(TopologyTexts.provenance(_m).size())
	assert_int(kinds[&"question"]).is_equal(TopologyTexts.questions(_m).size())
	page.free()
