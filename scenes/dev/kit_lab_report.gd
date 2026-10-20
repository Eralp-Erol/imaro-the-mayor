extends SceneTree
## kit_lab ölçüm raporu (render YOK; başsız çalışır): yerleşimi üretir, spec 3.2/3.3/4 ölçümlerini JSON
## basar.
##   tools/godot.sh --headless --path . -s res://scenes/dev/kit_lab_report.gd -- [--seed=N] [--out=/abs/x.json]


func _initialize() -> void:
	var seed_value := 20261020
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var lib := KitLibrary.load_manifest()
	var layout := KitLabLayout.new()
	layout.generate(lib, seed_value)
	var report := KitLabMetrics.full_report(lib, layout)
	var text := JSON.stringify(report, "\t")
	print("KIT_LAB_REPORT ", text)
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	quit(0)
