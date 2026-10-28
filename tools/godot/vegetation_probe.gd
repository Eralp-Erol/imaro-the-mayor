extends SceneTree
## Bitki yerleşimi/görünüm tanısı (T-062 B1), BAŞSIZ: oyunun dünya kurulumunu (playable ile aynı veri/tohum) yapar,
## `VegetationLoader` ile yerleşimi üretir/önbellekten alır ve kamera noktaları için kademe/leke sayılarını yazar.
##   tools/godot.sh --headless --path . --script res://tools/godot/vegetation_probe.gd -- [--no-cache] [--cam=x,y,z ...]
## Çıktı: JSON satırları (VEG_PROBE ...). Render/FPS ölçmez (dummy renderer).

const DATA_DIR := "res://data/world/ismeral"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var use_cache := true
	var cams: Array[Vector3] = []
	var presets: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-cache":
			use_cache = false
		elif arg.begins_with("--preset="):
			presets.append(arg.trim_prefix("--preset="))
		elif arg.begins_with("--cam="):
			var p := arg.trim_prefix("--cam=").split(",")
			cams.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	var t0 := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var world := WorldGenerator.generate(control, world_seed, {})
	var net_control: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	var rules_json: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/settlement.json" % DATA_DIR))
	var net := NetworkGenerator.generate(world, net_control as Dictionary, world_seed)
	var loaded := SettlementTable.load_game_table()
	var settlement := T0Settlement.generate_detailed(world, net, loaded["table"], world_seed, rules_json as Dictionary)
	print("VEG_PROBE world+settlement_ms ", snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1),
			" buildings ", settlement.columns.count)
	var species := VegetationSpecies.load_default()
	var rules := VegetationRules.load_path(VegetationRules.PATH, species)
	if OS.get_cmdline_user_args().has("--colors"):
		var full := VegetationLook.load_full(species, VegetationViewConfig.load_default())
		for i in full.count:
			print("VEG_PROBE color ", full.keys[i], " ", full.blob_color[i].to_html(false), " lod0 ",
					full.mesh_lod0[i] != null, " errors ", full.errors)
		quit(0)
		return
	var loader := VegetationLoader.start(settlement, species, rules, world, true, use_cache)
	print("VEG_PROBE loader ", JSON.stringify(loader.stats), " state ", loader.state)
	if loader.state != VegetationLoader.State.READY:
		quit(1)
		return
	for spec in presets:
		var r := CameraPresets.resolve(spec, world)
		var st: CameraState = r["state"]
		var ground := func(x: float, z: float) -> float: return maxf(world.height_at(x, z), world.sea_level)
		var eye := CameraMath.eye_relative(st, 0.0, 0.0, ground)
		print("VEG_PROBE preset ", spec, " focus ", Vector2(st.focus_x, st.focus_z), " dist ", st.distance, " eye ", eye)
		cams.append(eye)
	var cols := loader.columns
	var counts := cols.species_counts()
	var per_species := {}
	for i in species.size():
		per_species[species.keys[i]] = counts[i]
	print("VEG_PROBE instances ", cols.count, " cells ", cols.cell_keys.size(), " peak_cell ", cols.peak_cell(),
			" per_species ", JSON.stringify(per_species), " layers ", cols.layer_counts(), " hash ",
			cols.state_hash().substr(0, 16))
	var config := VegetationViewConfig.load_default()
	var lod := VegetationLod.from_config(config)
	var look := VegetationLook.numbers_only(species, config)
	for cam in cams:
		var res: Dictionary = _count_at(loader.layout, lod, cam, config)
		var blob_tris := 0
		var blob_clumps := 0
		var t1 := Time.get_ticks_usec()
		var chunks := VegetationWindow.chunks_to_open(loader.layout, cam, config.lod1_end_m, config.blob_end_m,
				config.blob_load_margin_m, config.blob_chunk_cells, {})
		for key in chunks:
			var built := VegetationBlobBuilder.build_chunk(loader.layout, look, config, key.x, key.y)
			blob_tris += int(built["tris"])
			blob_clumps += int(built["clumps"])
		res["blob_chunks"] = chunks.size()
		res["blob_tris_all"] = blob_tris
		res["blob_clumps_all"] = blob_clumps
		res["blob_build_ms"] = snappedf((Time.get_ticks_usec() - t1) / 1000.0, 0.1)
		print("VEG_PROBE cam ", cam, " ", JSON.stringify(res))
	quit(0)


## Kamera çevresinde kademe başına örnek ve ÜÇGEN sayısı (LOD0/LOD1/PROXY mesh'leri yüklü olmadan tablo sayılarından).
func _count_at(layout: VegetationLayout, lod: VegetationLod, cam: Vector3, config: VegetationViewConfig) -> Dictionary:
	var species := VegetationSpecies.load_default()
	var cols := layout.cols
	var n := [0, 0, 0]
	var tris := [0, 0, 0]
	var opened := VegetationWindow.cells_to_open(layout, lod, cam, config.load_margin_m, {})
	var cells_mixed := 0
	for k in opened:
		for run in VegetationCellBuilder.species_runs(cols, k):
			var sp := run.x
			var has_proxy := species.has_proxy(sp)
			var part := VegetationCellBuilder.partition(layout, run.y, run.z, layout.cell_origin(cols.cell_keys[k]),
					config.sink_m, cam, lod, has_proxy)
			var c: PackedInt32Array = part["counts"]
			n[0] += c[0]
			n[1] += c[1]
			n[2] += c[2]
			tris[0] += c[0] * species.tris_lod0[sp]
			tris[1] += c[1] * species.tris_lod1[sp]
			tris[2] += c[2] * species.tris_proxy[sp]
			cells_mixed += 1 if (c[0] > 0 and c[1] > 0) else 0
	return {"cells_open": opened.size(), "lod0": n[0], "lod1": n[1], "proxy": n[2], "tris_lod0": tris[0],
			"tris_lod1": tris[1], "tris_proxy": tris[2], "tris_trees": tris[0] + tris[1] + tris[2]}
