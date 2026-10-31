extends SceneTree
## T-042b OYUN KATMANI ölçümü/yakalaması: gerçek `playable.tscn` (gerçek dünya + T0 + sim + HUD + yol/bitki görünümü)
## üstünde
## binalı bloktan kamulaştırmalı yol -> onay -> tick -> yıkım -> geri al akışı. Sahnenin `_process`'i buradan sabit dt
## ile
## sürülür (kare süreleri ölçülür). Duvar saati yalnız ölçümdür (Intel Mac, iPad DEĞİL).
## Başsız (ölçüm):  tools/godot.sh --headless --path . --script res://tools/godot/expropriation_game_probe.gd --
## [--tries=400]
## Pencereli (görüntü): tools/godot.sh --path . --resolution 1600x900 --script
## res://tools/godot/expropriation_game_probe.gd -- \
##                      --shots=/private/tmp/claude-501/expropriation_game_screens [--ui] [--prefix=m2-t042b]
## `--ui`: yolu gerçek viewport girdisiyle (Viewport.push_input: fare tıkları, "Kamulaştırarak geç"/"Yıkımı onayla"
## düğmeleri)
## çizer; yoksa komut doğrudan gönderilir. Çıktı satırları: XPROBE_*.

const Support := preload("res://tests/game/expropriation_game_support.gd")
const SCENE := "res://scenes/game/playable.tscn"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const DT := 0.016667

var _args: Dictionary = {}
var _scene: Node = null
var _frame_ms: Array[float] = []
var _shots_dir: String = ""
var _prefix: String = "m2-t042b"
var _windowed: bool = false
## Kare izi (T-0xx yol onayı kare sivrilmeleri): her kare {stage, i, proc (sahne _process), input (bu kareden önce
## push_input), wall (kare başı -> bir sonraki process_frame)}. `--trace`: sivrilen kareler + aşama özeti yazılır.
var _stage: String = "setup"
var _stage_i: int = 0
var _trace: Array[Dictionary] = []
var _input_ms: float = 0.0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	_shots_dir = str(_args.get("shots", ""))
	_prefix = str(_args.get("prefix", "m2-t042b"))
	_windowed = DisplayServer.get_name() != "headless"
	if not _shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	if not _windowed:
		root.size = Vector2i(1600, 900)   # başsız betik penceresi 64x64: HUD/tık geometrisi için gerçekçi boyut
	var packed: PackedScene = load(SCENE)
	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	_scene.set_process(false)
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	if facade == null:
		push_error("probe: facade yok")
		quit(2)
		return
	print("XPROBE_SETUP ", JSON.stringify(_scene.sim_stats))
	for _i in 30:
		await _frame()
	var cand := _find_candidate(facade)
	if cand.is_empty():
		push_error("probe: aday yol yok")
		quit(3)
		return
	print("XPROBE_CANDIDATE ", JSON.stringify(cand["info"]))
	if _args.has("baseline"):
		await _baseline(cand)
	_set_stage("focus")
	await _focus_on(cand["a"], cand["b"], float(_args.get("distance", "230")))
	_set_stage("idle")
	await _shot("1-before")
	if _args.has("ui"):
		await _drive_road_ui(facade, cand)
	else:
		await _drive_road(facade, cand)
	await _shot("2-after-road")
	if _args.has("ui"):
		await _undo_ui(facade)
	else:
		await _undo(facade)
	await _shot("3-after-undo")
	if _args.has("trace"):
		_print_trace()
	quit(0)


## Bir kare: sahne `_process` + engine karesi. Süre (ms) toplanır.
func _frame(dt: float = DT) -> float:
	var t0 := Time.get_ticks_usec()
	_scene._process(dt)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_frame_ms.append(ms)
	await process_frame
	_trace.append({"stage": _stage, "i": _stage_i, "proc": ms, "input": _input_ms,
			"wall": (Time.get_ticks_usec() - t0) / 1000.0 + _input_ms})
	_stage_i += 1
	_input_ms = 0.0
	return ms


func _set_stage(name: String) -> void:
	_stage = name
	_stage_i = 0


## Aşama başına özet + eşiği aşan kareler (XPROBE_TRACE satırları). Eşik `--trace=<ms>` (varsayılan 8).
func _print_trace() -> void:
	var limit := float(_args.get("trace", "8"))
	var stages: Array[String] = []
	var peak: Dictionary = {}
	var count: Dictionary = {}
	var over16: Dictionary = {}
	for rec in _trace:
		var st: String = rec["stage"]
		if not peak.has(st):
			stages.append(st)
			peak[st] = 0.0
			count[st] = 0
			over16[st] = 0
		var step: float = float(rec["proc"]) + float(rec["input"])
		peak[st] = maxf(float(peak[st]), step)
		count[st] = int(count[st]) + 1
		if step > 16.0:
			over16[st] = int(over16[st]) + 1
		if step > limit:
			print("XPROBE_TRACE %s#%d proc=%.1f input=%.1f wall=%.1f" % [st, int(rec["i"]), float(rec["proc"]),
					float(rec["input"]), float(rec["wall"])])
	for st in stages:
		print("XPROBE_STAGE %s frames=%d peak_step_ms=%.1f over16=%d" % [st, int(count[st]), float(peak[st]), int(over16[st])])


func _find_candidate(facade: SimFacadeImpl) -> Dictionary:
	return Support.find_candidate(_scene, facade, StringName(str(_args.get("region", "D2"))), int(_args.get("seed", "7")),
			int(_args.get("tries", str(Support.SEG_TRIES))), int(_args.get("min_built", "3")))


## ÖNCE (naif yol): alınan parsellerin satırları süzülmüş SÜTUNLARLA tam `set_columns` (ayrı, geçici bir
## BuildingView'da):
## plan + hücre özetleri, çatı dizini ve yeniden kurulan hücre/süper-chunk'lar tek çağrıda, tek karede.
func _baseline(cand: Dictionary) -> void:
	var cols: BuildingColumns = _scene._t0_columns
	var cm: PackedInt64Array = cand["cm"]
	var taken := Support.taken_preview(_scene, cm)
	var drop := {}
	for pid in taken:
		drop[int(pid)] = true
	var kept := BuildingColumns.new()
	for i in cols.count:
		if not drop.has(cols.parcel_id[i]):
			kept.add(cols.parcel_id[i], cols.module_idx[i], cols.x[i], cols.z[i], cols.yaw[i], cols.floors[i],
					cols.wall_row[i], cols.roof_row[i], cols.accent_row[i], cols.bright[i], cols.flags[i], cols.era[i])
	var view: BuildingView = _scene._buildings
	var t0 := Time.get_ticks_usec()
	var plan := BuildingChunkPlan.build(kept, _scene._world.origin, view.config.cell_m, view.config.super_cells)
	var t1 := Time.get_ticks_usec()
	var hashes := plan.cell_hashes(kept)
	var t2 := Time.get_ticks_usec()
	var roofs := RoofClearance.new()
	roofs.set_from_columns(_scene._world, kept, _scene._kit)
	var t3 := Time.get_ticks_usec()
	print("XPROBE_BASELINE naif parçalar: BuildingChunkPlan.build %.1f ms | cell_hashes(%d hücre) %.1f ms | "
			% [(t1 - t0) / 1000.0, hashes.size(), (t2 - t1) / 1000.0]
			+ "RoofClearance.set_from_columns %.1f ms | taken=%d satır_düşen=%d" % [(t3 - t2) / 1000.0, taken.size(),
			cols.count - kept.count])
	var scratch: BuildingView = BuildingView.new()
	_scene.add_child(scratch)
	scratch.setup(_scene._world, _scene._kit, view.config)
	scratch.set_columns(cols, 1)
	await process_frame
	var t4 := Time.get_ticks_usec()
	var rep := scratch.set_columns(kept, 2)
	var naive_ms := (Time.get_ticks_usec() - t4) / 1000.0
	print("XPROBE_BASELINE naif TAM set_columns tek çağrı: %.1f ms rebuilt=%s supers=%s plan_ms=%s build_ms=%s"
			% [naive_ms, str(rep.get("rebuilt")), str(rep.get("supers_rebuilt")), str(rep.get("plan_ms")),
			str(rep.get("build_ms"))])
	scratch.queue_free()
	await process_frame


func _focus_on(a: Vector2, b: Vector2, distance: float) -> void:
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	var mid := (a + b) * 0.5
	st.focus_x = mid.x
	st.focus_z = mid.y
	st.distance = distance
	cam.apply_state(st, true)
	for _i in 6:
		await _frame()


func _drive_road(facade: SimFacadeImpl, cand: Dictionary) -> void:
	var net: WorldNetwork = _scene._net
	var hidden_before: int = _scene._pr.follow.taken_count()
	var graph_before := net.graph_hash()
	var cm: PackedInt64Array = cand["cm"]
	var t0 := Time.get_ticks_usec()
	var v_plain := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, false))
	var plain_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var v_x := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	var x_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("XPROBE_VALIDATE plain_ms=%.2f plain_reason=%s expropriating_ms=%.2f status=%s" % [plain_ms,
			String(v_plain.reason_key), x_ms, String(v_x.status)])
	t0 = Time.get_ticks_usec()
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	print("XPROBE_SUBMIT status=%s ms=%.2f" % [String(res.status), (Time.get_ticks_usec() - t0) / 1000.0])
	# Tick: sahne `_process` içinde sürülür (drive_usec); 1 gün = tick süresi kadar dt gerekir.
	_scene._facade.set_speed(SimFacade.SPEED_PAUSED)
	var tick0 := facade.current_tick()
	t0 = Time.get_ticks_usec()
	facade.advance(1)
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("XPROBE_TICK road_tick_ms=%.2f tick=%d->%d" % [tick_ms, tick0, facade.current_tick()])
	_frame_ms.clear()
	var frames := 0
	var pump_peak := 0.0
	while frames < 600:
		var ms := await _frame()
		frames += 1
		pump_peak = maxf(pump_peak, ms)
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break
	print("XPROBE_FRAMES after_tick frames=%d max_ms=%.2f stats=%s" % [frames, pump_peak,
			JSON.stringify(_scene._pr.follow.stats)])
	print("XPROBE_SERIES after_tick ", _series())
	print("XPROBE_RESULT hidden_t0=%d->%d parcels=%d graph_changed=%s works=%d" % [hidden_before,
			_scene._pr.follow.taken_count(), net.parcels.size(), str(net.graph_hash() != graph_before),
			facade.public_works().size()])
	print("XPROBE_BUILDINGS ", JSON.stringify(_scene._buildings.stats).substr(0, 0), JSON.stringify({
			"install_max_ms": _scene._buildings.stats.get("mask_install_max_ms"),
			"build_max_ms": _scene._buildings.stats.get("mask_build_max_ms")}))
	for _i in 12:
		await _frame()


## Gerçek viewport girdisi: Y -> A'ya tık -> B'ye hareket + tık -> "Kamulaştırarak geç" -> "Yıkımı onayla" -> tick.
func _drive_road_ui(facade: SimFacadeImpl, cand: Dictionary) -> void:
	var ctrl: RoadDrawController = _scene._pr.ctrl
	var tool: RoadDrawTool = ctrl.tool
	_set_stage("tool_open")
	_key(KEY_Y)
	await _frame()
	for _i in 6:
		await _frame()
	_set_stage("click_a")
	print("XPROBE_UI tool_active=%s step=%d" % [str(ctrl.is_active()), tool.step])
	_scene._facade.set_speed(SimFacade.SPEED_PAUSED)
	var a: Vector2 = cand["a"]
	var b: Vector2 = cand["b"]
	_scene._camera.input_profile.select_requested.connect(func(p: Vector2) -> void: print("XPROBE_SELECT ", p))
	await _click(_screen(a))
	await _frame()
	_set_stage("hover")
	print("XPROBE_UI after A step=%d start=%s msg=%s screen=%s win=%s cam_band=%s" % [tool.step, str(tool.start),
			String(tool.message), str(_screen(a)), str(root.size), String(_scene._camera.scale_band)])
	for k in 5:
		_move(_screen(a.lerp(b, float(k + 1) / 5.0)))
		await _frame()
		await _frame()
	_set_stage("click_b")
	await _click(_screen(b))
	for _i in 4:
		await _frame()
	var verdict_key: String = tool.verdict.reason_key if tool.verdict != null else "-"
	print("XPROBE_UI after B step=%d verdict=%s offer=%s" % [tool.step, verdict_key,
			str(not tool.offer().is_empty())])
	await _shot("1b-offer")
	_set_stage("accept")
	var accept := _find_button(UiText.t(&"expropriation.accept"))
	if accept == null:
		push_error("probe: 'Kamulaştırarak geç' düğmesi yok")
		quit(4)
		return
	await _click(accept.get_global_rect().get_center())
	for _i in 4:
		await _frame()
	print("XPROBE_UI after accept expropriate=%s demolishes=%s valid=%s" % [str(tool.expropriate), str(tool.demolishes()),
			str(tool.is_valid())])
	await _shot("1c-confirm")
	var confirm := _find_button(UiText.t(&"expropriation.confirm"))
	if confirm == null:
		push_error("probe: 'Yıkımı onayla' düğmesi yok")
		quit(5)
		return
	var graph_before := (_scene._net as WorldNetwork).graph_hash()
	_set_stage("confirm")
	await _click(confirm.get_global_rect().get_center())
	await _frame()
	_set_stage("after_tick")
	print("XPROBE_UI after confirm step=%d" % tool.step)
	var t0 := Time.get_ticks_usec()
	facade.advance(1)
	print("XPROBE_TICK road_tick_ms=%.2f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_frame_ms.clear()
	var frames := 0
	while frames < 600:
		await _frame()
		frames += 1
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break
	print("XPROBE_FRAMES after_tick frames=%d stats=%s" % [frames, JSON.stringify(_scene._pr.follow.stats)])
	print("XPROBE_SERIES after_tick ", _series())
	print("XPROBE_RESULT hidden_t0=%d graph_changed=%s works=%d step=%d" % [_scene._pr.follow.taken_count(),
			str((_scene._net as WorldNetwork).graph_hash() != graph_before), facade.public_works().size(), tool.step])
	for _i in 10:
		await _frame()


## Geri al: "Son yolu geri al" -> "Evet, geri al" -> tick.
func _undo_ui(facade: SimFacadeImpl) -> void:
	var tool: RoadDrawTool = _scene._pr.ctrl.tool
	_set_stage("undo_open")
	var undo := _find_button(UiText.t(&"road.undo_last"))
	if undo == null:
		push_error("probe: 'Son yolu geri al' düğmesi yok")
		quit(6)
		return
	await _click(undo.get_global_rect().get_center())
	for _i in 3:
		await _frame()
	var yes := _find_button(UiText.t(&"expropriation.undo_confirm"))
	if yes == null:
		push_error("probe: 'Evet, geri al' düğmesi yok")
		quit(7)
		return
	await _shot("2b-undo-confirm")
	_set_stage("undo_confirm")
	await _click(yes.get_global_rect().get_center())
	await _frame()
	_set_stage("after_undo")
	facade.advance(1)
	_frame_ms.clear()
	var frames := 0
	while frames < 600:
		await _frame()
		frames += 1
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break
	print("XPROBE_FRAMES after_undo frames=%d hidden_t0=%d works=%d stats=%s" % [frames, _scene._pr.follow.taken_count(),
			facade.public_works().size(), JSON.stringify(_scene._pr.follow.stats)])
	print("XPROBE_SERIES after_undo ", _series())
	print("XPROBE_UI undo done step=%d" % tool.step)
	for _i in 10:
		await _frame()


func _screen(world_xz: Vector2) -> Vector2:
	return Support.screen_of(_scene, world_xz)


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		var t0 := Time.get_ticks_usec()
		root.push_input(e)
		_input_ms += (Time.get_ticks_usec() - t0) / 1000.0
		await _frame()


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	var t0 := Time.get_ticks_usec()
	root.push_input(e)
	_input_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		var t0 := Time.get_ticks_usec()
		root.push_input(e)
		_input_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _find_button(text: String) -> Button:
	return Support.find_button(_scene._hud, text)


func _undo(facade: SimFacadeImpl) -> void:
	var t0 := Time.get_ticks_usec()
	var res := facade.submit_command(SimCommand.public_work_undo_last())
	print("XPROBE_UNDO submit status=%s" % String(res.status))
	facade.advance(1)
	print("XPROBE_UNDO tick_ms=%.2f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_frame_ms.clear()
	var frames := 0
	var peak := 0.0
	while frames < 600:
		var ms := await _frame()
		frames += 1
		peak = maxf(peak, ms)
		if frames > 3 and not _scene._pr.follow.busy() and not _scene._pr.sync.world_busy():
			break
	print("XPROBE_FRAMES after_undo frames=%d max_ms=%.2f hidden_t0=%d stats=%s" % [frames, peak,
			_scene._pr.follow.taken_count(), JSON.stringify(_scene._pr.follow.stats)])
	print("XPROBE_SERIES after_undo ", _series())
	for _i in 12:
		await _frame()


func _series() -> String:
	var parts: Array[String] = []
	for ms in _frame_ms.slice(0, 40):
		parts.append("%.1f" % ms)
	return " ".join(parts)


func _shot(name: String) -> void:
	if _shots_dir.is_empty() or not _windowed:
		return
	for _i in 4:
		await _frame()
	var path := "%s/%s-%s.png" % [_shots_dir, _prefix, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("XPROBE_SHOT ", path)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
