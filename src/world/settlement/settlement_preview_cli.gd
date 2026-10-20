extends SceneTree
## Dev aracı (T-005 ölçüt 4-5): dünya + ağ + yerleşim üretir, süre/bellek/sayıları ölçer, debug PNG'leri yazar.
##   tools/godot.sh --headless --path . -s res://src/world/settlement/settlement_preview_cli.gd -- [seed] [out_dir]
## Çıktı: <out_dir>/settlement-{height,era,roof,zone}-metro.png, <bölge>-height/roof yakın planlar, tower-square.png.
## Süre/bellek ölçümü Time/OS kullanır: bu bir araçtır, üreteç saf kalır.

const DATA_DIR := "res://data/world/ismeral"
## Yakın plan pencere yarı boyutları (m; konum DEĞİL, çıktı çerçevesi).
const DISTRICT_HALF_M := 1500.0
const YARD_HALF_M := 1800.0
const SQUARE_HALF_M := 200.0
const DISTRICT_PX := 0.4
const DEFAULT_OUT_DIR := "artifacts/screenshots/captures/world-settlement"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var control := WorldControlData.load_dir(DATA_DIR)
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	var settle_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/settlement.json" % DATA_DIR))
	var manifest_path := "res://assets/models/buildings/kit_manifest.json"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var world_seed := int(control["world"]["default_seed"])
	var settle_seed := int(args[0]) if args.size() > 0 else 20261020
	var out_dir := ProjectSettings.globalize_path("res://%s" % DEFAULT_OUT_DIR)
	if args.size() > 1:
		out_dir = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := WorldGenerator.generate(control, world_seed, {})
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var mem0 := OS.get_static_memory_usage()
	var t0 := Time.get_ticks_msec()
	var res := T0Settlement.generate_detailed(world, net, manifest, settle_seed, settle_control)
	var ms := Time.get_ticks_msec() - t0
	var mem := OS.get_static_memory_usage() - mem0
	var c := res.columns
	print("settlement: %d ms · %d buildings · mem +%.1f MB (columns %.2f MB) · hash %s" % [ms, c.count,
			mem / 1048576.0, float(c.count * (4 + 4 + 4 + 4 + 4 + 7)) / 1048576.0, c.state_hash()])
	print("stats: %s" % str(res.stats))
	print("topology: %s" % res.topology_hash())
	var violations := SettlementInvariants.check_all(res)
	print("invariant violations: %d %s" % [violations.size(), violations.slice(0, 5)])
	for code in WorldControlData.REGION_CODES:
		var d := SettlementStats.region_density(res, StringName(code))
		var mix := SettlementStats.region_mix(res, StringName(code))
		print("%s buildings %d · gfa/km2 %.0f · bld/km2 %.1f · mean floors %.2f · %s" % [code, d["buildings"],
				d["gfa_per_km2"], d["buildings_per_km2"], d["mean_floors"], str(mix)])
	print("roof all: %s" % str(SettlementStats.roof_shares(res, PackedInt32Array())))
	print("window500: %s" % str(SettlementStats.window_tile_max(res, 500.0, 40)))
	print("tower: %s · plaza: %s" % [str(SettlementStats.tower_frame(res)),
			str(SettlementStats.plaza_clear_report(res, 50.0))])
	var port_gap := INF
	var yard := 0
	for i in c.count:
		if (c.flags[i] & BuildingColumns.FLAG_PORT_YARD) != 0:
			yard += 1
			port_gap = minf(port_gap, float(world.shore_distance[world.world_to_index(c.x[i], c.z[i])]))
	print("port yard buildings %d · min shore distance %.0f m" % [yard, port_gap])
	var whole := Rect2(world.origin, world.size)
	for mode in ["height", "era", "roof", "zone"]:
		SettlementPreview.render(res, whole, 0.05, mode).save_png("%s/settlement-%s-metro.png" % [out_dir, mode])
	for code in ["D1", "D6", "D2", "D4"]:
		var hub := net.node_pos(int(net.hubs[StringName(code)]))
		var r := Rect2(hub - Vector2.ONE * DISTRICT_HALF_M, Vector2.ONE * 2.0 * DISTRICT_HALF_M)
		SettlementPreview.render(res, r, 0.4, "height").save_png("%s/settlement-%s-height.png" % [out_dir, code])
		SettlementPreview.render(res, r, 0.4, "roof").save_png("%s/settlement-%s-roof.png" % [out_dir, code])
	if res.tower_index >= 0:
		var tc := c.position_of(res.tower_index)
		var square := Rect2(tc - Vector2.ONE * SQUARE_HALF_M, Vector2.ONE * 2.0 * SQUARE_HALF_M)
		SettlementPreview.render(res, square, 2.5, "height") \
				.save_png("%s/settlement-tower-square.png" % out_dir)
	if net.hubs.has(&"port"):
		var p := net.node_pos(int(net.hubs[&"port"]))
		SettlementPreview.render(res, Rect2(p - Vector2.ONE * YARD_HALF_M, Vector2.ONE * 2.0 * YARD_HALF_M), 0.4, "zone") \
				.save_png("%s/settlement-yard-zone.png" % out_dir)
	print("png: %s" % out_dir)
	quit(0)
