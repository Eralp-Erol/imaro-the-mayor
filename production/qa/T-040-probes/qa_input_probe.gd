extends SceneTree
## QA T-040: gerçek playable.tscn'de girdi (W kaydırma, tekerlek yakınlaşma, dünya tıklaması -> imar akışı, Z) hâlâ çalışıyor mu.

func _initialize() -> void:
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await process_frame
	var cam = scene.get("_camera")
	var vp := root.get_viewport()
	var s0 = cam.target_state()
	var fx0: float = s0.focus_x
	var fz0: float = s0.focus_z
	var d0: float = s0.distance
	var down := InputEventKey.new()
	down.keycode = KEY_W
	down.physical_keycode = KEY_W
	down.pressed = true
	vp.push_input(down)
	for i in 20:
		await process_frame
	var up := down.duplicate()
	up.pressed = false
	vp.push_input(up)
	await process_frame
	var s1 = cam.target_state()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(500, 450)
	vp.push_input(wheel)
	var wr := wheel.duplicate()
	wr.pressed = false
	vp.push_input(wr)
	for i in 5:
		await process_frame
	var s2 = cam.target_state()
	print("QA_INPUT W: focus (%.1f,%.1f)->(%.1f,%.1f) moved=%s | wheel: distance %.1f->%.1f changed=%s" % [fx0, fz0,
			s1.focus_x, s1.focus_z, Vector2(fx0, fz0).distance_to(Vector2(s1.focus_x, s1.focus_z)) > 0.5, s1.distance,
			s2.distance, absf(s2.distance - s1.distance) > 0.01])
	var hud: HudRoot = scene.get("_hud")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = vp.get_visible_rect().size * 0.5
	print("QA_INPUT viewport=%s" % vp.get_visible_rect().size)
	vp.push_input(click)
	var cr := click.duplicate()
	cr.pressed = false
	vp.push_input(cr)
	for i in 5:
		await process_frame
	print("QA_INPUT click: selected=%s panel=%s" % [scene.get("_selected_parcel_id"), hud.panel_id()])
	quit(0)
