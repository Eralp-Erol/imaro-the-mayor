extends SceneTree
## Ana sahneyi pencereli çalıştırıp N kare sonra viewport'u PNG olarak kaydeder.
## Kullanım (tools/capture.sh sarar):
##   godot --path . [--resolution WxH] --script res://tools/godot/capture_frame.gd -- --out=/abs/x.png --frames=30 [--scene=res://x.tscn] [oyun argümanları]
## --scene yoksa run/main_scene kullanılır. --out/--frames/--scene dışındaki kullanıcı argümanları (ör. --visual-capture) oyuna olduğu gibi geçer.
## --headless ile ÇALIŞMAZ: dummy renderer görüntü üretmez.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out_path := ""
	var frames := 30
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			frames = maxi(2, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
	if out_path == "":
		printerr("capture_frame: --out=<png> gerekli")
		quit(2)
		return
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		printerr("capture_frame: sahne yok: '%s'" % scene_path)
		quit(2)
		return
	var packed: PackedScene = load(scene_path)
	root.add_child(packed.instantiate())
	for i in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		printerr("capture_frame: boş görüntü (headless mi?)")
		quit(3)
		return
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := image.save_png(out_path)
	print("CAPTURE_SAVED %s %dx%d err=%d" % [out_path, image.get_width(), image.get_height(), err])
	quit(0 if err == OK else 4)
