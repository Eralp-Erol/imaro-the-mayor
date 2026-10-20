extends SceneTree
## Dev aracı: dünya + ağ üretir, süre/bellek/sayıları ölçer, debug PNG'leri yazar (T-011 ölçüt 5).
## Kullanım:
##   tools/godot.sh --headless --path . -s res://src/world/network/network_preview_cli.gd -- [seed] [out_dir] [cell_m]
## Çıktı: <out_dir>/network-metro.png ve bölge yakın planları (network-D1.png ... network-yard.png,
## network-parcels.png).
## Headless'ta Image.save_png çalışır (yalnız render gerekmez). Süre/bellek ölçümü Time/OS kullanır: bu bir araçtır,
## üreteç saf kalır.

const DATA_DIR := "res://data/world/ismeral"
const DEFAULT_OUT_DIR := "artifacts/screenshots/captures/world-network"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var control := WorldControlData.load_dir(DATA_DIR)
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	var world_seed := int(args[0]) if args.size() > 0 else int(control["world"]["default_seed"])
	var out_dir := ProjectSettings.globalize_path("res://%s" % DEFAULT_OUT_DIR)
	if args.size() > 1:
		out_dir = args[1]
	var overrides := {}
	if args.size() > 2:
		overrides["cell_size_m"] = float(args[2])
	DirAccess.make_dir_recursive_absolute(out_dir)

	var t0 := Time.get_ticks_msec()
	var mem0 := OS.get_static_memory_usage()
	var world := WorldGenerator.generate(control, world_seed, overrides)
	var t1 := Time.get_ticks_msec()
	var mem1 := OS.get_static_memory_usage()
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var t2 := Time.get_ticks_msec()
	var mem2 := OS.get_static_memory_usage()
	var counts := net.counts()
	print("world: %d ms · network: %d ms · mem world +%.1f MB · network +%.1f MB" % [t1 - t0, t2 - t1,
			(mem1 - mem0) / 1048576.0, (mem2 - mem1) / 1048576.0])
	print("counts: %s" % str(counts))
	var t3 := Time.get_ticks_msec()
	var h := net.state_hash()
	print("state_hash: %d ms · %s" % [Time.get_ticks_msec() - t3, h])
	print("topology_hash: %s" % net.topology_hash())
	var violations := NetworkInvariants.check_all(net)
	print("invariant violations: %d" % violations.size())
	for v in violations.slice(0, 30):
		print("  - %s" % v)
	_report_kinds(net)

	_save(net, Rect2(world.origin, world.size), 0.05, {"parcels": false}, "%s/network-metro.png" % out_dir)
	for code in WorldControlData.REGION_CODES:
		if net.hubs.has(StringName(code)):
			var c := net.node_pos(int(net.hubs[StringName(code)]))
			_save(net, Rect2(c - Vector2(2600, 2600), Vector2(5200, 5200)), 0.3, {}, "%s/network-%s.png" % [out_dir, code])
	if net.hubs.has(&"port"):
		var p := net.node_pos(int(net.hubs[&"port"]))
		_save(net, Rect2(p - Vector2(1800, 1800), Vector2(3600, 3600)), 0.5, {}, "%s/network-yard.png" % out_dir)
	if net.hubs.has(&"D1"):
		var c1 := net.node_pos(int(net.hubs[&"D1"]))
		_save(net, Rect2(c1 - Vector2(350, 350), Vector2(700, 700)), 2.4, {}, "%s/network-parcels.png" % out_dir)
	print("png: %s" % out_dir)
	quit(0)


func _save(net: WorldNetwork, rect: Rect2, px_per_m: float, layers: Dictionary, path: String) -> void:
	NetworkPreview.render(net, rect, px_per_m, layers).save_png(path)


func _report_kinds(net: WorldNetwork) -> void:
	var kinds := {}
	for b: WorldBlock in net.blocks.values():
		kinds[String(b.kind)] = int(kinds.get(String(b.kind), 0)) + 1
	var fabrics := {}
	for p: WorldParcel in net.parcels.values():
		fabrics[String(p.fabric)] = int(fabrics.get(String(p.fabric), 0)) + 1
	var regions := {}
	for p: WorldParcel in net.parcels.values():
		regions[String(p.region_code)] = int(regions.get(String(p.region_code), 0)) + 1
	var classes := {}
	var length_km := {}
	for e: WorldRoadEdge in net.edges.values():
		classes[String(e.road_class)] = int(classes.get(String(e.road_class), 0)) + 1
		length_km[String(e.road_class)] = float(length_km.get(String(e.road_class), 0.0)) + e.length / 1000.0
	print("blocks by kind: %s" % str(kinds))
	print("parcels by fabric: %s" % str(fabrics))
	print("parcels by region: %s" % str(regions))
	print("edges by class: %s" % str(classes))
	print("km by class: %s" % str(length_km))
	print("hubs: %s" % str(net.hubs))
