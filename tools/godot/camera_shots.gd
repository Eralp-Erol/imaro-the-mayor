extends SceneTree
## Çok kareli kamera yakalaması (T-064): sahneyi BİR kez kurar, her `--shot` için kamerayı yerleştirip PNG alır
## (dünya kurulumu ~30 sn sürdüğünden tek pencerede 10+ kare). Pencereli çalışır (headless görüntü üretmez).
##   godot --path . --resolution 1600x900 --script res://tools/godot/camera_shots.gd -- --out-dir=/abs/dir
##     [--scene=res://scenes/dev/world_preview.tscn] [--frames=24] [--prefix=m2-t064]
##     --shot=ad|preset[|heading[|pitch[|distance]]]  (preset yerine `home:KOD` Home görünümünü verir; KOD boş = core)
## Diğer kullanıcı argümanları (örn. --envelope=legacy, --no-buildings) sahneye aynen geçer.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var out_dir := ""
	var frames := 24
	var prefix := "m2-t064"
	var scene_path := "res://scenes/dev/world_preview.tscn"
	var shots: Array[PackedStringArray] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-dir="):
			out_dir = arg.trim_prefix("--out-dir=")
		elif arg.begins_with("--frames="):
			frames = maxi(4, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--prefix="):
			prefix = arg.trim_prefix("--prefix=")
		elif arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--shot="):
			shots.append(arg.trim_prefix("--shot=").split("|"))
	if out_dir == "" or shots.is_empty():
		printerr("camera_shots: --out-dir=<dizin> ve en az bir --shot=ad|preset gerekli")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var scene := (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var rig: CameraRig = scene.camera()
	for shot in shots:
		var spec := shot[1] if shot.size() > 1 else "core"
		if spec.begins_with("home:"):
			rig.home_district = StringName(spec.trim_prefix("home:"))
			rig.go_home()
		else:
			rig.apply_preset(spec)
		if shot.size() > 2 and shot[2] != "" or shot.size() > 3 or shot.size() > 4:
			var s := rig.target_state()
			s.heading_deg = float(shot[2]) if shot.size() > 2 and shot[2] != "" else s.heading_deg
			s.pitch_deg = float(shot[3]) if shot.size() > 3 and shot[3] != "" else s.pitch_deg
			s.distance = float(shot[4]) if shot.size() > 4 and shot[4] != "" else s.distance
			rig.apply_state(s, true)
		for i in frames:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_viewport().get_texture().get_image()
		var path := "%s/%s-%s.png" % [out_dir, prefix, shot[0]]
		var err := image.save_png(path)
		var st := rig.current_state()
		print("SHOT %s err=%d focus=(%.0f,%.0f) dist=%.0f pitch=%.1f heading=%.0f band=%s fog=%.2f" % [path, err,
				st.focus_x, st.focus_z, st.distance, st.pitch_deg, st.heading_deg, rig.scale_band,
				rig.envelope.fog_strength(st.distance)])
	quit(0)
