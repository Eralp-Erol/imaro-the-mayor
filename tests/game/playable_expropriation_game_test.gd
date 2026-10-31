extends GdUnitTestSuite
## T-042b OYUN KATMANI (CAN-03, WLD-01, D-011) · GERÇEK `playable.tscn` (gerçek dünya + T0 + sim + HUD) üstünde,
## `Viewport.push_input` ile: binalı bloktan yol -> "Kamulaştırarak geç" -> "Yıkımı onayla" -> tick -> yalnız beklenen
## hücre/süper-chunk kurulur, alınan parselin T0 yapısı çizilmez, seçim alınan parseli bulmaz, sim `taken` der -> "Son
## yolu geri al" -> binalar geri gelir -> kaydet/yükle sonrası aynı sütun imzası. Sentetik olaylar gerçek fare/dokunma
## DEĞİLDİR (cihaz davranışı doğrulanmadı). Sahne kurulumu ~1 dk (başsız).

const Support := preload("res://tests/game/expropriation_game_support.gd")
const SCENE := "res://scenes/game/playable.tscn"
const VIEWPORT := Vector2i(1600, 900)

var _scene: Node = null
var _rebuilt: Array[Vector2i] = []


func after() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## Bekleyen görünüm işi (T0 filtresi, kent zemini, yol görünümü) bitene dek kare ilerler.
func _settle() -> int:
	var frames := 0
	while frames < 900:
		await get_tree().process_frame
		frames += 1
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break
	return frames


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e)
		await get_tree().process_frame


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		get_viewport().push_input(e)


func _focus(mid: Vector2) -> void:
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	st.focus_x = mid.x
	st.focus_z = mid.y
	st.distance = 230.0
	cam.apply_state(st, true)
	await _frames(6)


func test_road_through_a_built_block_demolishes_then_undo_restores_then_load_matches() -> void:
	get_window().size = VIEWPORT
	_scene = (load(SCENE) as PackedScene).instantiate()
	add_child(_scene)
	await _frames(3)
	var facade := _scene._facade as SimFacadeImpl
	assert_object(facade).is_not_null()
	facade.set_speed(SimFacade.SPEED_PAUSED)
	facade.advance(2)   # ilk tick ekonomi durumunu kurar (yol komutu `economy_not_started` demesin)
	var net: WorldNetwork = _scene._net
	var follow: PlayableExpropriation = _scene._pr.follow
	var view: BuildingView = _scene._buildings
	var cols: BuildingColumns = _scene._t0_columns
	assert_object(follow).is_not_null()
	for _i in 20:
		await get_tree().process_frame

	# --- aday: D2'de binalı bloktan geçen yol -------------------------------------------------------------------------
	var cand := Support.find_candidate(_scene, facade)
	assert_bool(cand.is_empty()).override_failure_message("aday yol bulunamadı").is_false()
	var a: Vector2 = cand["a"]
	var b: Vector2 = cand["b"]
	var cm: PackedInt64Array = cand["cm"]
	var preview_args: Dictionary = cand["info"]["args"]
	var taken_ids := Support.taken_preview(_scene, cm)
	assert_int(taken_ids.size()).is_equal(int(preview_args["taken_parcels"]))
	var occupied_before: Dictionary = (_scene._t0_occupied as Dictionary).duplicate()
	var t0_taken := PackedInt32Array()
	var centroids := {}
	for pid in taken_ids:
		centroids[int(pid)] = net.parcel(int(pid)).centroid
		if occupied_before.has(int(pid)):
			t0_taken.append(int(pid))
	assert_int(t0_taken.size()).is_equal(int(preview_args["taken_built_parcels"]))
	var drawn_before := Support.t0_drawn_parcels(_scene)
	for pid in t0_taken:
		assert_bool(drawn_before.has(int(pid))).is_true()
	var sig_before := Support.t0_signature(_scene)
	var parcels_before := net.parcels.size()
	var building_count := view.building_count()
	await _focus((a + b) * 0.5)

	# --- gerçek girdi: Y, A'ya tık, B'ye hareket + tık ----------------------------------------------------------------
	var tool: RoadDrawTool = _scene._pr.ctrl.tool
	_key(KEY_Y)
	await _frames(1)
	assert_bool(_scene._pr.ctrl.is_active()).is_true()
	await _click(Support.screen_of(_scene, a))
	assert_int(tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	for k in 5:
		_move(Support.screen_of(_scene, a.lerp(b, float(k + 1) / 5.0)))
		await _frames(2)
	await _click(Support.screen_of(_scene, b))
	await _frames(4)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_bool(tool.offer().is_empty()).override_failure_message("kamulaştırma teklifi yok").is_false()
	assert_int(int(tool.offer()["taken_built_parcels"])).is_equal(t0_taken.size())
	# Teklif aşamasında hiçbir şey değişmedi (önizleme yıkmaz).
	assert_int(net.parcels.size()).is_equal(parcels_before)
	var accept := Support.find_button(_scene._hud, UiText.t(&"expropriation.accept"))
	assert_object(accept).override_failure_message("'Kamulaştırarak geç' düğmesi yok").is_not_null()
	await _click(accept.get_global_rect().get_center())
	await _frames(4)
	assert_bool(tool.expropriate and tool.demolishes()).is_true()
	assert_int(facade.public_works().size()).is_equal(0)   # onaydan önce komut gönderilmedi
	# Aynı noktaya yeniden dokunuş yıkımlı yolu ONAYLAMAZ (kazara dokunuş).
	await _click(Support.screen_of(_scene, b))
	await _frames(2)
	assert_int(tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	var confirm := Support.find_button(_scene._hud, UiText.t(&"expropriation.confirm"))
	assert_object(confirm).override_failure_message("'Yıkımı onayla' düğmesi yok").is_not_null()
	await _click(confirm.get_global_rect().get_center())
	assert_int(tool.step).is_equal(RoadDrawTool.Step.SENDING)

	# --- tick: yol uygulanır, T0 yapıları süzülür ---------------------------------------------------------------------
	_rebuilt.clear()
	view.cells_rebuilt.connect(func(keys: Array) -> void: _rebuilt.append_array(keys))
	var nodes_before := {}
	for k in view.cell_keys():
		nodes_before[k] = view.cell_node(k)
	var supers_before := {}
	for k in view.super_keys():
		supers_before[k] = view.super_node(k)
	facade.advance(1)
	assert_int(facade.public_works().size()).is_equal(1)
	await _settle()
	assert_int(follow.taken_count()).is_equal(t0_taken.size())
	for pid in taken_ids:
		assert_bool(net.parcels.has(int(pid))).is_false()
	var drawn_after := Support.t0_drawn_parcels(_scene)
	for pid in t0_taken:
		assert_bool(drawn_after.has(int(pid))) \
				.override_failure_message("alınan parselin yapısı çiziliyor: %d" % pid).is_false()
		assert_bool((_scene._t0_occupied as Dictionary).has(int(pid))).is_false()
	assert_int(drawn_after.size()).is_equal(drawn_before.size() - t0_taken.size())
	assert_int(view.building_count()).is_less(building_count)
	# Yalnız beklenen hücre / süper-chunk kuruldu.
	var plan := view.plan()
	var want_cells := {}
	for pid in t0_taken:
		for r in (view._mask as BuildingParcelMask).rows_of(int(pid)):
			want_cells[plan.cell_of(cols.x[r], cols.z[r])] = true
	assert_int(_rebuilt.size()).is_greater(0)
	for k in _rebuilt:
		assert_bool(want_cells.has(k)).override_failure_message("beklenmeyen hücre kuruldu: %s" % str(k)).is_true()
	for k: Vector2i in nodes_before:
		if not want_cells.has(k):
			assert_object(view.cell_node(k)).is_same(nodes_before[k])
	var want_supers := {}
	for k: Vector2i in want_cells:
		want_supers[plan.super_of(k)] = true
	for k: Vector2i in supers_before:
		if not want_supers.has(k):
			assert_object(view.super_node(k)).is_same(supers_before[k])
	# Seçim alınan parseli bulmaz (dünya parseli yok); dünya tıklaması null'a hazır.
	var victim := int(t0_taken[0])
	var vc: Vector2 = centroids[victim]
	assert_int(net.parcel_id_at(vc.x, vc.y)).is_not_equal(victim)
	await _focus(vc)
	_scene._pr.ctrl.deactivate()   # araç açıkken dünya tıklaması yol çizimine gider
	_scene._on_select_requested(Support.screen_of(_scene, vc))
	assert_int(_scene._selected_parcel_id).is_not_equal(victim)
	# Sim parseli `taken` görür ve projector onun için satır üretmez.
	for v in facade.parcel_views(taken_ids):
		assert_str(String(v.development)).is_equal("taken")
	var proj_cols: BuildingColumns = _scene._projector.columns()
	for i in proj_cols.count:
		assert_bool(taken_ids.has(proj_cols.parcel_id[i])).is_false()

	# --- geri al (gerçek düğmeler) -----------------------------------------------------------------------------------
	_scene._pr.ctrl.activate()
	await _frames(3)
	var undo := Support.find_button(_scene._hud, UiText.t(&"road.undo_last"))
	assert_object(undo).override_failure_message("'Son yolu geri al' düğmesi yok").is_not_null()
	await _click(undo.get_global_rect().get_center())
	await _frames(3)
	assert_int(facade.public_works().size()).is_equal(1)   # ikinci adım onayı bekliyor
	var yes := Support.find_button(_scene._hud, UiText.t(&"expropriation.undo_confirm"))
	assert_object(yes).override_failure_message("'Evet, geri al' düğmesi yok").is_not_null()
	await _click(yes.get_global_rect().get_center())
	facade.advance(1)
	assert_int(facade.public_works().size()).is_equal(0)
	await _settle()
	assert_int(follow.taken_count()).is_equal(0)
	assert_str(Support.t0_signature(_scene)).is_equal(sig_before)
	assert_int(view.building_count()).is_equal(building_count)
	for pid in taken_ids:
		assert_bool(net.parcels.has(int(pid))).is_true()
	for pid in t0_taken:
		assert_bool((_scene._t0_occupied as Dictionary).has(int(pid))).is_true()
	for v in facade.parcel_views(taken_ids):
		assert_str(String(v.development)).is_not_equal("taken")

	# --- kaydet / yükle: aynı sütun imzası -----------------------------------------------------------------------------
	_scene._pr.ctrl.deactivate()
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	assert_bool(res.is_rejected()).is_false()
	facade.advance(1)
	await _settle()
	var sig_road := Support.t0_signature(_scene)
	assert_str(sig_road).is_not_equal(sig_before)
	var bytes := facade.export_save()
	var hash_road := facade.state_hash()
	facade.submit_command(SimCommand.public_work_undo_last())
	facade.advance(1)
	await _settle()
	assert_str(Support.t0_signature(_scene)).is_equal(sig_before)
	var loaded := facade.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(str(loaded.message)).is_true()
	_scene.resync_sim_buildings_after_load()
	await _settle()
	assert_str(facade.state_hash()).is_equal(hash_road)
	assert_str(Support.t0_signature(_scene)).is_equal(sig_road)
	assert_int(follow.taken_count()).is_equal(t0_taken.size())
	# Köprü takılı olduğundan yükleme `network_mismatch` vermedi (yukarıdaki ok), taban ağ geri alınınca da döner.
	facade.submit_command(SimCommand.public_work_undo_last())
	facade.advance(1)
	await _settle()
	assert_str(Support.t0_signature(_scene)).is_equal(sig_before)
