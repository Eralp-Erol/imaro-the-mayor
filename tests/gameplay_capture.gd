extends RefCounted
## Runs in the real rendered application. UI actions use actual input dispatch.

var game: Node3D
var checks: Array[String] = []
var failures: Array[String] = []

func wait_frames(count: int = 3) -> void:
	for i in range(count): await game.get_tree().process_frame

func check(condition: bool, label_text: String) -> void:
	checks.append(label_text)
	if not condition: failures.append(label_text)

func click(position: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		Input.parse_input_event(event)
		await wait_frames(2)

func capture(name_text: String) -> void:
	await game.get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var result: Error = game.get_viewport().get_texture().get_image().save_png("res://artifacts/screenshots/" + name_text + ".png")
	check(result == OK, name_text + " gerçek viewport görüntüsü")

func run(application: Node3D) -> void:
	game = application
	await game.get_tree().create_timer(0.6).timeout
	await capture("03-gameplay-overview")
	# Selecting via the visible parcel collider, not a direct state mutation.
	game.hud.panel.hide()
	var p: CityModel.Parcel = game.sim.parcels[23]
	var screen: Vector2 = game.rig.camera.unproject_position(Vector3(p.geometry.x, 0.8, p.geometry.z))
	print("INPUT_PROBE ", {"world_screen": screen, "ray_hit": game.district.pick_ray(game.rig.camera, screen), "viewport": game.get_viewport().get_visible_rect(), "root": game.hud.root.size, "transform": game.get_viewport().get_screen_transform(), "button": game.hud.propose_button.get_global_rect()})
	await click(screen)
	check(game.hud.selected == 23 and game.hud.panel.visible, "Dünya dokunuşu gerçek özel parseli seçer")
	await click(game.hud.propose_button.get_global_rect().get_center())
	check(game.sim.pending_for(23), "Gerçek HUD tıklaması imar teklifi gönderir")
	check(game.sim.parcels[23].use == "empty", "HUD bina spawn etmez")
	for i in range(3): game.sim.tick()
	await wait_frames()
	game.camera_action("focus")
	await game.get_tree().create_timer(0.5).timeout
	check(game.sim.parcels[23].use == "construction", "Meclis ve piyasa sonucunda şantiye görünür")
	await capture("04-construction")
	for i in range(18): game.sim.tick()
	await wait_frames()
	check(game.sim.parcels[23].use == "apartment", "Zamana bağlı inşaat tamamlanır")
	await capture("05-completed")
	game.hud.open_tab(3)
	await capture("06-neighborhood-reaction")
	# Camera input through the same event route used by a mouse.
	game.hud.panel.hide()
	var old_target: Vector3 = game.rig.target
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(360, 300)
	Input.parse_input_event(down)
	await wait_frames()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(440, 340)
	motion.relative = Vector2(80, 40)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await wait_frames()
	down = down.duplicate()
	down.pressed = false
	down.position = motion.position
	Input.parse_input_event(down)
	await wait_frames()
	check(game.rig.target.distance_to(old_target) > 1 and not game.hud.panel.visible, "Sürükleme kamerayı kaydırır, parsel tıklaması üretmez")
	var old_zoom: float = game.rig.desired_zoom
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(400, 300)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await wait_frames()
	check(game.rig.desired_zoom < old_zoom, "Tekerlek yakınlaştırır")
	var old_yaw: float = game.rig.yaw
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await wait_frames()
	check(game.rig.yaw != old_yaw, "E tuşu kamerayı döndürür")
	game.camera_action("home")
	game.select_parcel(19)
	game.hud.zones.select(0)
	game.hud.refresh()
	await click(game.hud.propose_button.get_global_rect().get_center())
	for i in range(3): game.sim.tick()
	await wait_frames()
	check(game.sim.parcels[19].use == "empty" and game.sim.parcels[19].zone == "housing", "Olumsuz yatırım senaryosu gerçek oyunda boş kalır")
	await capture("07-investment-declined")
	game.toggle_weather()
	game.hud.open_tab(2)
	await capture("08-cloudy-budget")
	var metrics := {"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	DirAccess.make_dir_recursive_absolute("res://artifacts/tests")
	var file := FileAccess.open("res://artifacts/tests/gameplay.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "metrics": metrics, "renderer": "Compatibility / desktop OpenGL", "physical_ipad_tested": false}, "\t"))
	file.close()
	print("GAMEPLAY: %d/%d passed; %s" % [checks.size() - failures.size(), checks.size(), str(metrics)])
	for failure in failures: printerr("FAIL: " + failure)
	game.get_tree().quit(0 if failures.is_empty() else 1)
