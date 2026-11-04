extends Control
## T-056 library comparison. Each column has an isolated world with the SAME
## camera transform/light: LOD0 | LOD1 | PROXY. No production world/loader usage.
## --fam=old_core|bazaar|res_mid|res_late|house|industrial|civic
## --variant=a|b|c --distance=40 --variants=true --view=front|rear --yaw=DEGREES --benchmark=true
const FAMILIES := ["old_core", "bazaar", "res_mid", "res_late", "house", "industrial", "civic"]
const LEVELS := ["LOD0", "LOD1", "PROXY"]
var _args := {}
var _frames := 0
var _samples: Array[float] = []
var _views: Array[SubViewport] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	var family := String(_args.get("fam", "old_core"))
	assert(family in FAMILIES, "Unknown hero family")
	var variants := [String(_args.get("variant", "a"))]
	if _args.get("variants", "false") == "true":
		variants = ["a", "b", "c"]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	add_child(grid)
	for variant in variants:
		for level in LEVELS:
			_add_cell(grid, family, variant, level)
	if _args.get("benchmark", "false") == "true":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _path(family: String, variant: String, level: String) -> String:
	if level != "LOD0":
		return "res://assets/hero/lod/hero_%s_%s_%s.glb" % [family, variant, level.to_lower()]
	if family == "old_core":
		return "res://assets/hero/hero_%s.glb" % variant
	return "res://assets/hero/fam/hero_%s_%s.glb" % [family, variant]


func _add_cell(grid: GridContainer, family: String, variant: String, level: String) -> void:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_child(panel)
	var label := Label.new()
	label.text = "%s / %s · %s · %s m" % [family, variant, level, _args.get("distance", "40")]
	label.text += " · arka" if _args.get("view", "front") == "rear" else ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(container)
	var view := SubViewport.new()
	view.size = Vector2i(520, 650)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(view)
	_views.append(view)
	var root := Node3D.new()
	view.add_child(root)
	var building := (load(_path(family, variant, level)) as PackedScene).instantiate() as Node3D
	root.add_child(building)
	for child in building.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		for surface in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat:
				var copy := mat.duplicate() as BaseMaterial3D
				copy.roughness = 1.0
				copy.metallic_specular = 0.0
				copy.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
				copy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				mesh.set_surface_override_material(surface, copy)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.70, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.74)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.light_energy = 0.5
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.rotation_degrees = Vector3(-38, -35, 0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.70, 0.67, 0.60)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	ground.position.y = -0.04
	root.add_child(ground)
	var bounds := AABB()
	# Always frame using original LOD0 bounds, regardless of selected level.
	var original := (load(_path(family, variant, "LOD0")) as PackedScene).instantiate() as Node3D
	for child in original.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		bounds = bounds.merge(mesh.transform * mesh.get_aabb())
	original.free()
	var target := bounds.get_center()
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.far = 1000.0
	root.add_child(camera)
	var yaw := float(_args.get("yaw", 180.0 if _args.get("view", "front") == "rear" else 0.0))
	var direction := Vector3(0.38, 0.22, 1.0).normalized().rotated(Vector3.UP, deg_to_rad(yaw))
	camera.position = target + direction * float(_args.get("distance", "40"))
	camera.look_at(target, Vector3.UP)
	camera.make_current()


func _process(delta: float) -> void:
	if _args.get("benchmark", "false") != "true":
		return
	_frames += 1
	if _frames > 60:
		_samples.append(delta * 1000.0)
	if _samples.size() != 180:
		return
	var total := 0.0
	for sample in _samples:
		total += sample
	_samples.sort()
	var stats := {
		"family": _args.get("fam", "old_core"),
		"distance_m": float(_args.get("distance", "40")),
		"samples": _samples.size(),
		"mean_frame_ms": total / _samples.size(),
		"p95_frame_ms": _samples[int(_samples.size() * 0.95)],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"scope": "three isolated comparison viewports, not production load",
	}
	print("HERO_LOD_BENCH ", JSON.stringify(stats))
	get_tree().quit()
