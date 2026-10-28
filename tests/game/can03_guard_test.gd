extends GdUnitTestSuite
## T-040 ölçüt 8 · CAN-03 koruması (olumsuz test): oyuncu doğrudan yapı ekleyemez; `BuildingColumns` / `BuildingView`
## girdisini sim durumundan üreten TEK yol SimBuildingProjector'dır. Statik tarama (kaynak metni) + davranış testi.

## `BuildingColumns` üreten / dolduran dosyalar (yalnız bunlar): T0 üreteci, sim projector (dev stand-in
## `DevBuildingSource` T-062 A3'te kaldırıldı).
const COLUMN_PRODUCERS := [
	"res://src/world/settlement/building_columns.gd",
	"res://src/world/settlement/t0_settlement.gd",
	"res://src/world/settlement/settlement_result.gd",
	"res://src/view/buildings/sim_building_projector.gd",
	"res://src/view/buildings/sim_building_placer.gd",
	"res://src/game/playable_stock.gd",
	"res://src/view/buildings/building_view.gd",
]
## `set_columns(` çağıran / tanımlayan dosyalar.
const SET_COLUMNS_USERS := [
	"res://src/view/buildings/building_view.gd",
	"res://src/game/playable.gd",
	"res://scenes/dev/world_preview.gd",
]
## Komut / HUD / sözleşme / sim / platform kodu yapı geometrisine HİÇ dokunmaz.
const FORBIDDEN_DIRS := ["res://src/ui", "res://src/sim", "res://src/contracts", "res://src/app"]
const FORBIDDEN_TOKENS := ["BuildingColumns", "BuildingView", "set_columns", "SimBuildingProjector"]
## Projector yazma yolu kullanamaz: yalnız okuma metodları.
const PROJECTOR_FORBIDDEN := ["submit_command", "SimCommand", "InputEvent", "advance(", "import_save", "set_speed",
		"validate_command", "game_state"]


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append("%s/%s" % [dir, f])
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files("%s/%s" % [dir, d]))
	return out


## Kaynak metni, yorum satırları ve satır sonu yorumları çıkarılmış (belgelerdeki adlar tarama sonucunu etkilemez).
func _text(path: String) -> String:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		out.append(line)
	return "\n".join(out)


func test_static_only_known_producers_create_building_columns() -> void:
	var offenders := PackedStringArray()
	for path in _gd_files("res://src") + _gd_files("res://scenes"):
		var text := _text(path)
		if text.contains("BuildingColumns.new(") and not COLUMN_PRODUCERS.has(path):
			offenders.append(path)
	assert_array(offenders).override_failure_message(
			"BuildingColumns üreten bilinmeyen dosya: %s" % str(offenders)).is_empty()


func test_static_set_columns_is_called_only_by_the_view_and_the_scene_glue() -> void:
	var offenders := PackedStringArray()
	for path in _gd_files("res://src") + _gd_files("res://scenes"):
		if _text(path).contains("set_columns(") and not SET_COLUMNS_USERS.has(path):
			offenders.append(path)
	assert_array(offenders).override_failure_message(
			"set_columns çağıran bilinmeyen dosya: %s" % str(offenders)).is_empty()


func test_static_the_sim_view_is_fed_only_by_the_projector() -> void:
	var text := _text("res://src/game/playable.gd")
	var rx := RegEx.create_from_string("_sim_buildings\\.set_columns\\((.*)\\)")
	var calls := rx.search_all(text)
	assert_int(calls.size()).override_failure_message("sim görünümüne tek besleme noktası beklenir").is_equal(1)
	assert_str(calls[0].get_string(1)).starts_with("columns, version")
	# O tek nokta (`_apply_sim_view`) yalnız şu yerlerden çağrılır: dev tam senkron ve yükleme sonrası eşitleme (ikisi de
	# projector sütunları) ve kare dağıtıcısı (SimBuildingPump, yalnız projector.columns() verir).
	var uses := RegEx.create_from_string("_apply_sim_view").search_all(text)
	assert_int(uses.size()).override_failure_message("_apply_sim_view: tanım + 3 kullanım beklenir").is_equal(4)
	assert_int(text.split("_apply_sim_view(_projector.columns(), _projector.version())").size() - 1).is_equal(2)
	assert_bool(text.contains("_pump.frame(ticked, _apply_sim_view)")).is_true()
	var pump := _text("res://src/view/buildings/sim_building_pump.gd")
	assert_bool(pump.contains("apply_view.call(projector.columns(), _seen_version)")).is_true()
	assert_int(RegEx.create_from_string("apply_view\\.call").search_all(pump).size()).is_equal(1)
	# T0 görünümü yalnız T0 üretecinin sütunlarını alır; sim görünümüne başka bir değişken verilmez.
	assert_bool(text.contains("_sim_buildings.set_columns(cols")).is_false()


func test_static_sim_view_uses_the_same_lod_config_object_as_the_t0_view() -> void:
	# T-012 LOD sözleşmesi: SimBuildings, T0 görünümüyle AYNI BuildingViewConfig örneğini kullanır (mesafe LOD0/LOD1/HLOD).
	var text := _text("res://src/game/playable.gd")
	assert_bool(text.contains("_buildings.setup(_world, _kit, config)")).is_true()
	assert_bool(text.contains("_sim_buildings.setup(_world, _kit, config)")).is_true()
	assert_int(RegEx.create_from_string("BuildingViewConfig\\.new\\(\\)").search_all(text).size()).is_equal(1)


func test_static_command_hud_contract_sim_and_app_code_never_touch_building_geometry() -> void:
	var offenders := PackedStringArray()
	for dir in FORBIDDEN_DIRS:
		for path in _gd_files(dir):
			var text := _text(path)
			for token in FORBIDDEN_TOKENS:
				if text.contains(token):
					offenders.append("%s: %s" % [path, token])
	assert_array(offenders).override_failure_message(
			"yapı geometrisine dokunan komut/HUD/sim kodu: %s" % str(offenders)).is_empty()


func test_static_projector_is_read_only_toward_the_sim_and_ignores_player_input() -> void:
	for path in ["res://src/view/buildings/sim_building_projector.gd", "res://src/view/buildings/sim_building_placer.gd"]:
		var text := _text(path)
		for token in PROJECTOR_FORBIDDEN:
			assert_bool(text.contains(token)).override_failure_message("%s: yasak simge %s" % [path, token]).is_false()


func test_behaviour_without_a_player_command_no_sim_rows_appear() -> void:
	var h := M2RenderSupport.handle(M2RenderSupport.ISOLATE)   # otonom tarama kapalı: yalnız komut karar tetikler
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	for day in 120:
		f.advance(1)
		proj.sync()
	proj.sync(true)
	assert_int(proj.columns().count).override_failure_message("komutsuz sim satırı").is_equal(0)
	var outcome := f.economy_outcome()
	assert_int(outcome.investments_approved).is_equal(0)


func test_behaviour_a_direct_building_command_is_rejected_and_adds_no_rows() -> void:
	var h := M2RenderSupport.handle(M2RenderSupport.ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 1)
	for kind: StringName in [&"building.place", &"private.build", &"spawn.building"]:
		assert_bool(SimCommand.is_forbidden_kind(kind)).is_true()
		var cmd := SimCommand.make(kind, {"parcel_ids": ids})
		var res := f.submit_command(cmd)
		assert_bool(res.is_rejected()).override_failure_message("%s kabul edildi" % kind).is_true()
	for day in 60:
		f.advance(1)
		proj.sync()
	proj.sync(true)
	assert_int(proj.columns().count).is_equal(0)


func test_behaviour_rows_exist_only_after_command_and_investor_decision() -> void:
	var h := M2RenderSupport.handle(M2RenderSupport.ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 2)
	f.advance(3)
	proj.sync()
	assert_int(proj.columns().count).is_equal(0)
	assert_bool(f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed")).is_rejected()).is_false()
	f.advance(1)
	proj.sync()
	assert_int(proj.columns().count).override_failure_message("öneri anında (karar öncesi) yapı çıkmamalı").is_equal(0)
	for day in 160:
		f.advance(1)
		proj.sync()
	proj.sync(true)
	assert_int(proj.columns().count).is_greater(0)
	for pid in proj.columns().occupied_parcels():
		assert_bool(ids.has(pid)).override_failure_message("öneri verilmeyen parselde sim satırı").is_true()
