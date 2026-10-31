extends SceneTree
## Yol birleşim (T / uçtan uca) görsel kırığı yakalama ve geometri raporu (2026-10-31).
## PENCERELİ çalışır (başsız dummy renderer görüntü üretmez):
##   tools/godot.sh --path . --resolution 1280x720 \
##     --script res://tools/godot/junction_probe.gd -- --out=/abs/dir --tag=before
## Gerçek Ismeral dünyasında, oyuncunun çizim yolunun aynısıyla (RoadDraftCheck.apply -> planarizer) mevcut yola
## T ve uçtan uca bağlanan yollar çizer; RoadView ile üst ve eğik görünümde PNG alır. Sayısal geometri ölçümü
## tests/view/roads/road_junction_geometry_test.gd'dedir. Üretim kodu değildir.

const DATA_DIR := "res://data/world/ismeral"
const SHOT_SIZE_M := 56.0

var _out := "/private/tmp/claude-501/junction_screens"
var _tag := "run"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--tag="):
			_tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(_out)
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var world := WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var rules := RoadDraftRules.from_control(net_control)
	rules.jurisdiction_regions = []
	var scenarios := _scenarios(net, rules)
	var view_holder := Node3D.new()
	root.add_child(view_holder)
	var view := RoadView.new()
	view_holder.add_child(view)
	view.build(net, RoadStyle.load_default())
	var shot := 0
	for sc: Dictionary in scenarios:
		print("JUNCTION %s node=%d at=%s edges=%s" % [sc["name"], sc["node"], str(sc["at"]), str(sc["edges"])])
		await _shoot(world, sc, shot)
		shot += 1
	quit(0)


## Her senaryo ağa kalıcı eklenir (uzak yerlerde): {name, at (Vector2), node, edges}.
func _scenarios(net: WorldNetwork, rules: RoadDraftRules) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = net.edges.keys()
	ids.sort()
	var used: Array[Vector2] = []
	# (ad, mevcut sınıf, açı derece, yeni sınıf)
	var plan := [["t90_local_on_collector", &"collector", 90.0, &"local"],
			["t60_local_on_collector", &"collector", 60.0, &"local"],
			["t35_local_on_collector", &"collector", 35.0, &"local"],
			["t90_local_on_local", &"local", 90.0, &"local"],
			["t90_collector_on_local", &"local", 90.0, &"collector"],
			["t90_local_on_arterial", &"arterial", 90.0, &"local"]]
	for entry: Array in plan:
		var found := false
		for eid: int in ids:
			var e: WorldRoadEdge = net.edges[eid]
			if e.road_class != entry[1] or e.mode() != &"road" or e.length < 120.0 or e.layer != WorldRoadEdge.LAYER_BASE:
				continue
			var a := net.node_pos(e.a)
			var b := net.node_pos(e.b)
			var mid := a.lerp(b, 0.5)
			if _near(used, mid, 400.0):
				continue
			var dir := (b - a).normalized()
			for side: float in [1.0, -1.0]:
				var ang: float = deg_to_rad(float(entry[2])) * side
				var pts := PackedVector2Array([mid, mid + dir.rotated(ang) * 120.0])
				var res := RoadDraftCheck.apply(net, pts, entry[3], rules)
				if bool(res["applied"]):
					used.append(mid)
					var report: Dictionary = res["report"]
					out.append({"name": entry[0], "at": mid, "node": _node_at(net, mid),
							"edges": report.get("added_edges", []), "end": pts[1], "dir": (pts[1] - pts[0]).normalized()})
					found = true
					break
			if found:
				break
	# Uçtan uca: oyuncunun az önce çizdiği yolun serbest ucundan devam (hafif kıvrılarak ya da düz).
	var first_count := out.size()
	var turns := [0.0, 25.0, -40.0]
	for i in mini(first_count, turns.size()):
		var sc: Dictionary = out[i]
		var start: Vector2 = sc["end"]
		var dir: Vector2 = sc["dir"]
		var turn: float = turns[i]
		var res := RoadDraftCheck.apply(net, PackedVector2Array([start, start + dir.rotated(deg_to_rad(turn)) * 100.0]),
				&"local", rules)
		if bool(res["applied"]):
			out.append({"name": "end_to_end_turn%d" % int(turn), "at": start, "node": _node_at(net, start),
					"edges": (res["report"] as Dictionary).get("added_edges", [])})
	# İki mevcut yolu birbirine bağlayan yeni yol (iki ucu da T).
	for eid: int in ids:
		if out.size() >= first_count + turns.size() + 2:
			break
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != &"road" or e.length < 100.0 or e.layer != WorldRoadEdge.LAYER_BASE:
			continue
		var m1 := net.node_pos(e.a).lerp(net.node_pos(e.b), 0.5)
		if _near(used, m1, 400.0):
			continue
		for other: int in ids:
			var f: WorldRoadEdge = net.edges[other]
			if other == eid or f.mode() != &"road" or f.length < 100.0:
				continue
			var m2 := net.node_pos(f.a).lerp(net.node_pos(f.b), 0.5)
			var d := m1.distance_to(m2)
			if d < 50.0 or d > 140.0:
				continue
			var res := RoadDraftCheck.apply(net, PackedVector2Array([m1, m2]), &"local", rules)
			if bool(res["applied"]):
				used.append(m1)
				out.append({"name": "bridge_two_roads", "at": m1.lerp(m2, 0.5), "node": -1,
						"edges": (res["report"] as Dictionary).get("added_edges", [])})
				break
	return out


func _near(list: Array[Vector2], p: Vector2, r: float) -> bool:
	for q in list:
		if q.distance_to(p) < r:
			return true
	return false


func _node_at(net: WorldNetwork, p: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for nid: int in net.nodes:
		var d := net.node_pos(nid).distance_to(p)
		if d < best_d:
			best_d = d
			best = nid
	return best


func _shoot(world: WorldData, sc: Dictionary, index: int) -> void:
	var at: Vector2 = sc["at"]
	var h := world.height_at(at.x, at.y)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.42, 0.22)
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground.material_override = gm
	ground.position = Vector3(at.x, h - 0.5, at.y)
	root.add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	root.add_child(light)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	for view_name in ["top", "oblique"]:
		if view_name == "top":
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = SHOT_SIZE_M
			cam.position = Vector3(at.x, h + 80.0, at.y)
			cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 50.0
			cam.position = Vector3(at.x + 28.0, h + 26.0, at.y + 34.0)
			cam.look_at(Vector3(at.x, h, at.y), Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var path := "%s/%s_%02d_%s_%s.png" % [_out, _tag, index, sc["name"], view_name]
		image.save_png(path)
		print("SHOT %s" % path)
	ground.queue_free()
	light.queue_free()
	cam.queue_free()
