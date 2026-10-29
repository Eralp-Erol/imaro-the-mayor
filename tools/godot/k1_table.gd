extends SceneTree
## K1 tablosunu `CameraEnvelope` ile yeniden üretir (T-064 ölçüt 2; ADR-0007 §Bağlam tablosu), BAŞSIZ. Düz deniz düzlemi
## (zemin yok), FOV 40 derece, veri zarfı. Her bölge çapası için: preset (uzaklık, DIŞA yön) için gereken en küçük eğim
## (16:9), çapada K1'li en büyük uzaklık (16:9 / 4:3, en dik eğim, dışa yön) ve İÇE bakışla aynı iki sayı.
##   tools/godot.sh --headless --path . --script res://tools/godot/k1_table.gd
## Çıktı: Markdown satırları (K1_TABLE ...). Kodda ilçe kimliği yok: bölgeler dünya verisinden gelir.

const DATA_DIR := "res://data/world/ismeral"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var control := WorldControlData.load_dir(DATA_DIR)
	var world := WorldGenerator.generate(control, int(control["world"]["default_seed"]), {"cell_size_m": 400.0})
	var env := CameraEnvelope.load_default()
	var bounds := world.bounds()
	var center := bounds.get_center()
	var no_ground := Callable()
	var wide := 16.0 / 9.0
	var narrow := 4.0 / 3.0
	var core := CameraPresets.core(world, env)
	print("K1_TABLE | Odak | Preset (uzaklık km, yön) | Gereken min. eğim 16:9 (4:3) | Çapada K1'li en büyük uzaklık 16:9 / 4:3 km"
			+ " | İçe bakışla: min. eğim, 16:9 / 4:3 km |")
	print("K1_TABLE | Dünya merkezi (d_max) | %.1f km | %.1f° (%.1f°) | %.1f / %.1f | — |" % [
			core.distance / 1000.0, env.required_pitch(core, wide, no_ground, bounds),
			env.required_pitch(core, narrow, no_ground, bounds),
			env.max_distance_at(core, wide, no_ground, bounds) / 1000.0,
			env.max_distance_at(core, narrow, no_ground, bounds) / 1000.0])
	for region in world.regions:
		var out_s := CameraPresets.district(world, region.code)
		# district() artık İÇE bakar; DIŞA yönü (eski preset) çapa - merkez yönünden kurarız.
		var away := region.anchor - center
		var out_dir := out_s.copy()
		if away.length() >= CameraPresets.DISTRICT_MIN_HEADING_OFFSET_M:
			out_dir.heading_deg = wrapf(rad_to_deg(atan2(away.x, -away.y)), 0.0, 360.0)
		var line := "K1_TABLE | %s | %.1f km, %.0f° (dışa) | " % [region.code, out_dir.distance / 1000.0, out_dir.heading_deg]
		var req_w := env.required_pitch(out_dir, wide, no_ground, bounds)
		var req_n := env.required_pitch(out_dir, narrow, no_ground, bounds)
		line += "%s (%s) | %.1f / %.1f | " % [_deg(req_w), _deg(req_n),
				env.max_distance_at(out_dir, wide, no_ground, bounds) / 1000.0,
				env.max_distance_at(out_dir, narrow, no_ground, bounds) / 1000.0]
		line += "%s, %.1f / %.1f |" % [_deg(env.required_pitch(out_s, wide, no_ground, bounds)),
				env.max_distance_at(out_s, wide, no_ground, bounds) / 1000.0,
				env.max_distance_at(out_s, narrow, no_ground, bounds) / 1000.0]
		print(line)
	quit(0)


func _deg(value: float) -> String:
	return "çözümsüz" if value < 0.0 else "%.1f°" % value
