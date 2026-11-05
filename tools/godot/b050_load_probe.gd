extends SceneTree
## B-050 olcum probu (B-025 yukleme-supurme artigi): gercek `playable.tscn` akisinda kaydet -> yukle, sonra kare yolunda
## (`_process`, `SimBuildingPump`) sim yapilarinin ve T0 binalarinin eksik cizilip cizilmedigini sayar.
## Akis: kamulastirmali yol -> yikim -> belediye arazisi `zone.residential` (municipal_reuse) -> gun ilerlet -> KAYIT.
## Asamalar: live (kayit anindaki canli durum), same (ayni surecte import + resync + kare yolu), fresh (YENI playable
## sureci, tick 0'dan import + resync + kare yolu = oyuncunun gercek yuklemesi).
## Calistir (basli veya pencereli):
##   tools/godot.sh --headless --path . --script res://tools/godot/b050_load_probe.gd -- [--min-built=3] [--days=130]
## Cikti: B050_*. Duvar saati yalnizca olcumdur (Intel Mac, iPad DEGIL).

const Support := preload("res://tests/game/expropriation_game_support.gd")
const DT := 0.016667
const SETTLE_CAP := 6000

var _args: Dictionary = {}
var _scene: Node = null
## Yolun kamulastirdigi T0 YAPILI parsel kimlikleri (yol komutu sonrasi, yikimdan once): T0 gorunumu bunlari gizlemeli.
var _taken_t0: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1600, 900)
	await _boot()
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	print("B050_BOOT0 ", JSON.stringify(_census("boot0")))
	var cand := Support.find_candidate(_scene, facade, &"D2", int(str(_args.get("seed", "7"))), 400,
			int(str(_args.get("min-built", "3"))))
	if cand.is_empty():
		push_error("probe: aday yol yok")
		quit(3)
		return
	var road := facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
	print("B050_ROAD status=%s reason=%s args=%s" % [String(road.status), String(road.reason_key),
			JSON.stringify(road.args)])
	facade.advance(1)
	await _settle(false)
	var works := facade.public_works()
	if works.is_empty():
		push_error("probe: yol uygulanmadi")
		quit(4)
		return
	var t0_cols: BuildingColumns = _scene._t0_columns
	var t0_all := {}
	for pid in t0_cols.occupied_parcels():
		t0_all[int(pid)] = true
	for pid in works[works.size() - 1].taken_parcel_ids:
		if t0_all.has(int(pid)):
			_taken_t0[int(pid)] = true
	print("B050_TAKEN_T0 n=%d ids=%s" % [_taken_t0.size(), str(_taken_t0.keys())])
	var demo_r := facade.submit_command(SimCommand.public_work_demolish(works[works.size() - 1].command_id))
	print("B050_DEMOLISH status=%s reason=%s" % [String(demo_r.status), String(demo_r.reason_key)])
	var lands: Array[MunicipalLandView] = []
	for _d in 60:
		facade.advance(1)
		lands = facade.municipal_lands()
		var avail := 0
		for l in lands:
			avail += 1 if l.available else 0
		if avail > 0 and avail == lands.size():
			break
	await _settle(false)
	var ids := PackedInt64Array()
	for l in lands:
		if l.available:
			ids.append(l.id)
	print("B050_LANDS total=%d available=%d" % [lands.size(), ids.size()])
	var plan := facade.submit_command(SimCommand.zoning_propose(ids, &"zone.residential", true))
	print("B050_ZONING status=%s reason=%s" % [String(plan.status), String(plan.reason_key)])
	var days := int(str(_args.get("days", "130")))
	for _d in days / 10:
		facade.advance(10)
		await _settle(false)
	await _settle(true)
	var live := _census("live")
	print("B050_CENSUS ", JSON.stringify(live))
	var bytes := facade.export_save()
	print("B050_SAVE bytes=%d tick=%d" % [bytes.size(), facade.current_tick()])
	# --- ayni surecte yukle ---
	var t0 := Time.get_ticks_usec()
	var imported := facade.import_save(bytes)
	var import_ms := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_scene.resync_sim_buildings_after_load()
	var resync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("B050_LOAD same ok=%s import_ms=%.1f resync_ms=%.1f" % [str(imported.ok), import_ms, resync_ms])
	print("B050_CENSUS ", JSON.stringify(_census("same-after-resync")))
	var same_settle := await _settle(true)
	print("B050_SETTLE same ", JSON.stringify(same_settle))
	print("B050_CENSUS ", JSON.stringify(_census("same-settled")))
	if _args.has("no-fresh"):
		quit(0)
		return
	# --- yeni surecte (yeni playable) yukle ---
	_scene.queue_free()
	await process_frame
	await process_frame
	await _boot()
	facade = _scene._facade as SimFacadeImpl
	t0 = Time.get_ticks_usec()
	imported = facade.import_save(bytes)
	import_ms = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_scene.resync_sim_buildings_after_load()
	resync_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("B050_LOAD fresh ok=%s import_ms=%.1f resync_ms=%.1f msg=%s" % [str(imported.ok), import_ms, resync_ms,
			imported.message])
	print("B050_CENSUS ", JSON.stringify(_census("fresh-after-resync")))
	var fresh_settle := await _settle(true)
	print("B050_SETTLE fresh ", JSON.stringify(fresh_settle))
	print("B050_CENSUS ", JSON.stringify(_census("fresh-settled")))
	quit(0)


func _boot() -> void:
	var packed: PackedScene = load("res://scenes/game/playable.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	_scene.set_process(false)
	for _i in 30:
		await _frame()
	_scene._facade.set_speed(SimFacade.SPEED_PAUSED)


## Kare yolu: sahnenin `_process`'i (pompa + projector dilimi + yol/T0 takibi). Sure ms.
func _frame() -> float:
	var t0 := Time.get_ticks_usec()
	_scene._process(DT)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	await process_frame
	return ms


## Projector/T0 takibi/gorunum sakinlesene dek kare surer. `strict`: tavana (SETTLE_CAP) kadar bekler.
func _settle(strict: bool) -> Dictionary:
	var frames := 0
	var max_ms := 0.0
	var sum_ms := 0.0
	var quiet := 0
	while frames < SETTLE_CAP:
		var ms: float = await _frame()
		frames += 1
		sum_ms += ms
		max_ms = maxf(max_ms, ms)
		if _quiet():
			quiet += 1
			if quiet >= (20 if strict else 3):
				break
		else:
			quiet = 0
	return {"frames": frames, "ms_sum": snappedf(sum_ms, 0.1), "ms_max": snappedf(max_ms, 0.1), "quiet": quiet}


func _quiet() -> bool:
	var proj: SimBuildingProjector = _scene._projector
	if proj != null and (proj.busy() or _scene._pump.view_pending()):
		return false
	var follow: PlayableExpropriation = _scene._pr.follow
	return not follow.busy()


## Sim ile cizilen arasindaki fark. Beklenen sim yapisi: developed_by_sim + yapi evresi + birim > 0.
func _census(label: String) -> Dictionary:
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	var proj: SimBuildingProjector = _scene._projector
	var t0_occ: Dictionary = _scene._t0_occupied
	var net: WorldNetwork = _scene._net
	var sim_build := {}
	var dev_counts := {}
	var all := facade.parcel_ids()
	var pos := 0
	while pos < all.size():
		var chunk := all.slice(pos, mini(pos + 400, all.size()))
		pos += chunk.size()
		for v in facade.parcel_views(chunk):
			if not v.developed_by_sim:
				continue
			dev_counts[String(v.development)] = int(dev_counts.get(String(v.development), 0)) + 1
			if v.use != ParcelView.USE_NONE and v.units > 0 and (v.development == ParcelView.DEVELOPMENT_BUILT
					or v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION
					or v.development == ParcelView.DEVELOPMENT_STALLED):
				sim_build[v.id] = true
	var shown := {}
	if proj != null:
		for pid in proj.parcel_ids():
			shown[int(pid)] = true
	var missing: Array = []
	var missing_t0: Array = []
	var unplaced_n := 0
	for pid: int in sim_build:
		if shown.has(pid):
			continue
		if proj != null and proj.is_unplaced(pid):
			unplaced_n += 1
			continue
		missing.append(pid)
		if t0_occ.has(pid):
			missing_t0.append(pid)
	missing.sort()
	var extra := 0
	for pid: int in shown:
		extra += 0 if sim_build.has(pid) else 1
	var t0_expected := 0
	var t0_drawn_set := Support.t0_drawn_parcels(_scene)
	var t0_missing := 0
	var t0_ghost := 0
	for pid: int in t0_occ:
		if net.parcels.has(pid):
			t0_expected += 1
			t0_missing += 0 if t0_drawn_set.has(pid) else 1
		else:
			t0_ghost += 1 if t0_drawn_set.has(pid) else 0
	var sb: BuildingView = _scene._sim_buildings
	var taken_drawn := 0
	var taken_in_net := 0
	for pid: int in _taken_t0:
		taken_drawn += 1 if t0_drawn_set.has(pid) else 0
		taken_in_net += 1 if net.parcels.has(pid) else 0
	var follow: PlayableExpropriation = _scene._pr.follow
	return {"label": label, "tick": facade.current_tick(), "sim_dev": dev_counts, "sim_building_parcels": sim_build.size(),
			"projector_rows": proj.columns().count if proj != null else -1, "projector_parcels": shown.size(),
			"unplaced": unplaced_n, "MISSING_sim": missing.size(), "MISSING_sim_of_t0": missing_t0.size(),
			"missing_ids": missing.slice(0, 20), "projector_extra": extra,
			"t0_occupied": t0_occ.size(), "t0_expected_drawn": t0_expected, "t0_drawn": t0_drawn_set.size(),
			"T0_TAKEN_STILL_DRAWN": taken_drawn, "taken_t0_in_net": taken_in_net, "taken_t0": _taken_t0.size(),
			"net_graph_version": net.graph_version, "follow_seen": follow._seen_version, "follow_taken": follow._taken.size(),
			"T0_MISSING": t0_missing, "T0_GHOST_taken_but_drawn": t0_ghost, "sim_view_stats": sb.stats if sb != null else {},
			"proj_full_syncs": int(proj.stats.get("full_syncs", 0)) if proj != null else -1,
			"proj_parcel_reads": int(proj.stats.get("parcel_reads", 0)) if proj != null else -1}
