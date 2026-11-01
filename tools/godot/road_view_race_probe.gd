extends SceneTree
## B-020 yeniden üretim: yol görünümü işçi iş parçacığı chunk verisi kurarken (`RoadView.compute_chunk_data`) ana
## iş parçacığı, dünya "meşgul" iken yıkım önizlemesi (`validate_command(public_work_demolish)`) ister; panel
## meşgulken de bunu tekrar tekrar yapar. Sözleşme: meşgulken ağ DEĞİŞMEZ. Hata varsa (a) `RPROBE_BUSY_PREVIEW`
## satırında graph_version değişir (çıkış 1) ve (b) günlükte `Out of bounds get index '<kenar/düğüm kimliği>' (on base:
## 'Dictionary')` (road_junction.gd:34, road_mesh_builder.gd:62/67) görülür: `grep -c "Out of bounds" <günlük>`.
## Başsız: tools/godot.sh --headless --path . --script res://tools/godot/road_view_race_probe.gd -- [--rounds=6]
## İki GERÇEK kamulaştırmalı yol gerekir (aday bulunamazsa çıkış 3). Çıktı satırları: RPROBE_*.

const Support := preload("res://tests/game/expropriation_game_support.gd")
const DT := 0.016667

var _scene: Node = null


func _initialize() -> void:
	run.call_deferred()


func _frame() -> void:
	_scene._process(DT)
	await process_frame


func run() -> void:
	var rounds := 6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.trim_prefix("--rounds="))
	var packed: PackedScene = load("res://scenes/game/playable.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	_scene.set_process(false)
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	for _i in 30:
		await _frame()
	facade.set_speed(SimFacade.SPEED_PAUSED)
	var first := Support.find_candidate(_scene, facade, &"D2", 7, 400, 0)
	var second := Support.find_candidate(_scene, facade, &"D2", 23, 400, 0)
	for cand: Dictionary in [first, second]:
		if cand.is_empty():
			push_error("probe: aday yol yok")
			quit(3)
			return
		var res := facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
		print("RPROBE_ROAD status=%s" % String(res.status))
		facade.advance(1)
		for _i in 20:
			await _frame()
	var waited := 0
	while waited < 900 and (_scene._pr.follow.busy() or _scene._pr.sync.world_busy() or waited < 60):
		await _frame()
		waited += 1
	var ids: Array[int] = []
	for w in facade.public_works():
		ids.append(w.command_id)
	print("RPROBE_WORKS %s" % str(ids))
	if ids.size() < 2:
		push_error("probe: iki ayakta yol gerekir")
		quit(3)
		return
	var roads: RoadView = _scene._pr.sync._roads
	var plan: RoadChunkPlan = roads.plan()
	var keys: Array[Vector2i] = plan.keys()
	var net: WorldNetwork = _scene._pr.sync._net
	var ctx: PublicWorksContext = facade._public_works
	ctx.busy_probe = func() -> bool: return true   # görünüm işi sürüyormuş gibi
	var v0 := net.graph_version
	var r := facade.validate_command(SimCommand.public_work_demolish(ids[0]))
	var mutated := net.graph_version != v0
	print("RPROBE_BUSY_PREVIEW reason=%s graph_version %d -> %d mutated=%s" % [String(r.reason_key), v0, net.graph_version,
			str(mutated)])
	for round in rounds:
		var holder := {"meshes": {}}
		var task := WorkerThreadPool.add_task(func() -> void: holder["meshes"] = roads.compute_chunk_data(keys, plan),
				false, "race")
		var n := 0
		while not WorkerThreadPool.is_task_completed(task):
			ctx.demolition_memo_key = ""   # ikinci yol için kuru koşu önbellek ıskası (liste açıkken olan)
			facade.validate_command(SimCommand.public_work_demolish(ids[n % ids.size()]))
			n += 1
		WorkerThreadPool.wait_for_task_completion(task)
		var changed := net.graph_version != v0
		mutated = mutated or changed
		print("RPROBE_ROUND %d previews=%d meshes=%d graph_version=%d" % [round, n, (holder["meshes"] as Dictionary).size(),
				net.graph_version])
	print("RPROBE_END mutated_while_busy=%s" % str(mutated))
	quit(1 if mutated else 0)
