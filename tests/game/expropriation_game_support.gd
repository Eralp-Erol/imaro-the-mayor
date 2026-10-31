class_name ExpropriationGameSupport
extends RefCounted
## T-042b OYUN KATMANI ortak yardımcılar (test paketi değildir): gerçek `playable.tscn` sahnesinde binalı bloktan geçen
## kamulaştırmalı bir yol adayı bulur, dünya noktasını ekrana çevirir, HUD'da düğme bulur ve oyunun ürettiği durumun
## imzasını verir. `tests/game/playable_expropriation_game_test.gd` ve `tools/godot/expropriation_game_probe.gd`
## kullanır.

const SEG_TRIES := 400


## {a, b, cm, info} ya da boş. Aday: `region` içinde bir yol kenarından başlayan 60-160 m'lik düz doğru; sim önizlemesi
## (`expropriate: true`) geçerli ve en az `min_built` yapılı parsel alıyor; `score` yapılı sayısı ağırlıklı, alınan
## sayısı ~8'e yakın olanı seçer. Sim'e yazmaz (yalnız `validate_command`).
static func find_candidate(scene: Node, facade: SimFacadeImpl, region: StringName = &"D2", seed_value: int = 7,
		tries: int = SEG_TRIES, min_built: int = 3, min_vacant: int = 0) -> Dictionary:
	var net: WorldNetwork = scene._net
	var world: WorldData = scene._world
	var occupied: Dictionary = scene._t0_occupied
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = net.edges.keys()
	ids.sort()
	var best: Dictionary = {}
	var best_score := -1000000
	for n in tries:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		if e.mode() != WorldNetwork.MODE_ROAD:
			continue
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		if net.rules.region_code_at(world, a) != region:
			continue
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 160.0)
		var cm := PackedInt64Array([roundi(a.x * 100.0), roundi(a.y * 100.0), roundi(b.x * 100.0), roundi(b.y * 100.0)])
		var res := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
		if res.is_rejected():
			continue
		var built := int(res.args.get("taken_built_parcels", 0))
		var taken := int(res.args.get("taken_parcels", 0))
		if built < min_built or taken - built < min_vacant:
			continue
		var score := built * 10 - absi(taken - 8)
		if score > best_score:
			best_score = score
			best = {"a": a, "b": b, "cm": cm, "info": {"a": [snappedf(a.x, 0.1), snappedf(a.y, 0.1)],
					"b": [snappedf(b.x, 0.1), snappedf(b.y, 0.1)], "args": res.args, "occupied_total": occupied.size()}}
	return best


## Dünya noktası -> ekran (arazi yüksekliği dahil; kamera rebasing dahil).
static func screen_of(scene: Node, world_xz: Vector2) -> Vector2:
	var rig: CameraRig = scene._camera
	var o := rig.rebase_origin
	var y: float = scene._terrain.surface_height_at(world_xz.x, world_xz.y)
	return rig.camera.unproject_position(Vector3(world_xz.x - o.x, y, world_xz.y - o.y))


## HUD ağacında görünür, metni birebir eşleşen düğme (yoksa null).
static func find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := find_button(child, text)
		if found != null:
			return found
	return null


## Alınacak T0 parsellerinin kimlikleri (yola `taken` önizlemesi): dünya ağından, ağa dokunmadan.
static func taken_preview(scene: Node, cm: PackedInt64Array) -> PackedInt64Array:
	var net: WorldNetwork = scene._net
	var checked := RoadDraftCheck.check(net, RoadDraftCheck.points_from_cm(cm), RoadDrawTool.ROAD_CLASS,
			NetworkExpropriationPort.new(net, RoadDraftRules.load_path(PlayableRoads.NETWORK_PATH)).rules)
	if not bool(checked["ok"]):
		return PackedInt64Array()
	return RoadDraftCheck.taken_parcels(net, checked["points"], RoadDrawTool.ROAD_CLASS)


## T0 görünümünün çizilen yapı imzası: hücre -> yapı konumları + parsel kimlikleri (sütun dizinine bağlı değil).
static func t0_signature(scene: Node) -> String:
	var view: BuildingView = scene._buildings
	var cols: BuildingColumns = scene._t0_columns
	var parts: Array[String] = []
	for k in view.cell_keys():
		var data := view.cell_summary(k)
		var at: Array[String] = []
		for i in data.kept:
			at.append("%d@%.0f,%.0f" % [cols.parcel_id[i], cols.x[i], cols.z[i]])
		at.sort()
		parts.append("%s:%s" % [str(k), ";".join(at)])
	return "|".join(parts)


## Çizilen T0 yapılarının parsel kimlikleri kümesi.
static func t0_drawn_parcels(scene: Node) -> Dictionary:
	var view: BuildingView = scene._buildings
	var cols: BuildingColumns = scene._t0_columns
	var out := {}
	for k in view.cell_keys():
		for i in view.cell_summary(k).kept:
			out[int(cols.parcel_id[i])] = true
	return out
