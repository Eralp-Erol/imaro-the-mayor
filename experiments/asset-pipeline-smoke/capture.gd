extends SceneTree
## Windowed capture: camera + light + asset, wait 2 frames, save smoke.png next to project.godot.
## Run: Godot --path experiments/asset-pipeline-smoke --resolution 800x600 -s capture.gd

func _initialize() -> void:
	var root := get_root()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	root.add_child(sun)
	root.add_child((load("res://assets/bld_smoke_5f.glb") as PackedScene).instantiate())
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(17, 26, 24), Vector3(0, 6, 0))
	cam.current = true
	# a flat ground reference
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.45, 0.3)
	pm.material = gm
	root.add_child(ground)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://smoke.png")
	var err := img.save_png(out)
	print("saved %s (%dx%d) err=%d" % [out, img.get_width(), img.get_height(), err])
	quit(0 if err == OK else 1)
