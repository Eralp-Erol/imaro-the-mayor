extends RefCounted
## Runs in the real rendered application. UI actions use actual input dispatch.

var game: Node3D
var checks: Array[String] = []
var failures: Array[String] = []
var screenshots: Array[Dictionary] = []

func wait_frames(count: int = 3) -> void:
	for i in range(count): await game.get_tree().process_frame

func check(condition: bool, label_text: String) -> void:
	checks.append(label_text)
	print(("PASS: " if condition else "FAIL: ") + label_text)
	if not condition: failures.append(label_text)

func dispatch(event: InputEvent) -> void:
	# All mouse coordinates here are logical viewport coordinates.
	if event is InputEventMouse: event.global_position = event.position
	game.get_viewport().push_input(event, true)

func click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	dispatch(motion)
	# Deliver one click in one input frame. The physical desktop cursor must not
	# inject a hover-exit between our synthetic press and release.
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		dispatch(event)
	await wait_frames(3)

func capture(name_text: String) -> void:
	await game.get_tree().create_timer(0.3).timeout
	# Request a normal engine frame with all HUD drawing commands refreshed.
	# Drawing the renderer manually mid-frame can capture incomplete Control text.
	for item in game.hud.root.find_children("*", "CanvasItem", true, false):
		item.queue_redraw()
	await RenderingServer.frame_post_draw
	var result: Error = game.get_viewport().get_texture().get_image().save_png("res://artifacts/screenshots/" + name_text + ".png")
	check(result == OK, name_text + " gerçek viewport görüntüsü")
	screenshots.append({"file": name_text + ".png", "day": game.sim.day, "parcel_24": game.sim.parcels[23].use, "totals": game.sim.totals()})

func advance_to(target_day: int) -> void:
	await click(game.hud.time_buttons[2].get_global_rect().get_center())
	check(game.clock.speed == 4, "HUD 4× kontrolü zamanı başlatır · hedef gün %d" % target_day)
	if game.clock.speed != 4: return
	var deadline := Time.get_ticks_msec() + 20000
	while game.sim.day < target_day and Time.get_ticks_msec() < deadline:
		await game.get_tree().create_timer(0.05).timeout
	await click(game.hud.time_buttons[0].get_global_rect().get_center())
	check(game.sim.day >= target_day and game.clock.speed == 0, "Gerçek oyun saati hedefe ulaşır ve HUD duraklatır · gün %d" % target_day)

func run(application: Node3D) -> void:
	game = application
	# A failed or interrupted capture must not leave an older success report in place.
	DirAccess.remove_absolute("res://artifacts/tests/gameplay.json")
	game.get_tree().create_timer(90).timeout.connect(func():
		printerr("GAMEPLAY_TIMEOUT: day=%d speed=%d" % [game.sim.day, game.clock.speed])
		game.get_tree().quit(1))
	await game.get_tree().create_timer(0.6).timeout
	await capture("03-gameplay-overview")
	# Selecting via the visible parcel collider, not a direct state mutation.
	game.select_parcel(19)
	game.hud.panel.hide()
	var p: CityModel.Parcel = game.sim.parcels[23]
	var screen: Vector2 = game.rig.camera.unproject_position(Vector3(p.geometry.x, 0.8, p.geometry.z))
	check(game.district.pick_ray(game.rig.camera, screen) == 23, "Viewport koordinatı beklenen parsel collider'ına gider")
	await click(screen)
	check(game.hud.selected == 23 and game.hud.panel.visible, "Dünya dokunuşu gerçek özel parseli seçer")
	await click(game.hud.propose_button.get_global_rect().get_center())
	check(game.sim.pending_for(23), "Gerçek HUD tıklaması imar teklifi gönderir")
	check(game.sim.parcels[23].use == "empty", "HUD bina spawn etmez")
	await advance_to(3)
	await wait_frames()
	game.camera_action("focus")
	await game.get_tree().create_timer(0.5).timeout
	check(game.sim.parcels[23].use == "construction", "Meclis ve piyasa sonucunda şantiye görünür")
	if game.sim.parcels[23].use == "construction": await capture("04-construction")
	await advance_to(12)
	if game.sim.parcels[23].use == "construction": await capture("04b-construction-progress")
	await advance_to(21)
	await wait_frames()
	check(game.sim.parcels[23].use == "apartment", "Zamana bağlı inşaat tamamlanır")
	if game.sim.parcels[23].use == "apartment": await capture("05-completed")
	game.hud.open_tab(3)
	await capture("06-neighborhood-reaction")
	# Camera input through the same event route used by a mouse.
	game.hud.panel.hide()
	var old_target: Vector3 = game.rig.target
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(360, 300)
	dispatch(down)
	await wait_frames()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(440, 340)
	motion.relative = Vector2(80, 40)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	dispatch(motion)
	await wait_frames()
	down = down.duplicate()
	down.pressed = false
	down.position = motion.position
	dispatch(down)
	await wait_frames()
	check(game.rig.target.distance_to(old_target) > 1 and not game.hud.panel.visible, "Sürükleme kamerayı kaydırır, parsel tıklaması üretmez")
	var old_zoom: float = game.rig.desired_zoom
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(400, 300)
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	dispatch(wheel)
	await wait_frames()
	check(game.rig.desired_zoom < old_zoom, "Tekerlek yakınlaştırır")
	var old_yaw: float = game.rig.yaw
	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	dispatch(key)
	await wait_frames()
	check(game.rig.yaw != old_yaw, "E tuşu kamerayı döndürür")
	game.camera_action("home")
	game.select_parcel(19)
	game.hud.zones.select(0)
	game.hud.refresh()
	await click(game.hud.propose_button.get_global_rect().get_center())
	await advance_to(game.sim.day + 3)
	await wait_frames()
	check(game.sim.parcels[19].use == "empty" and game.sim.parcels[19].zone == "housing", "Olumsuz yatırım senaryosu gerçek oyunda boş kalır")
	await capture("07-investment-declined")
	game.toggle_weather()
	game.hud.open_tab(2)
	await capture("08-cloudy-budget")
	var metrics := {"fps": Engine.get_frames_per_second(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	DirAccess.make_dir_recursive_absolute("res://artifacts/tests")
	var file := FileAccess.open("res://artifacts/tests/gameplay.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots, "metrics": metrics,
		"input_route": "Viewport.push_input(event, true)", "time_route": "HUD 4x / real _process / HUD pause",
		"renderer": "Compatibility / desktop OpenGL", "physical_ipad_tested": false}, "\t"))
	file.close()
	print("GAMEPLAY: %d/%d passed; %s" % [checks.size() - failures.size(), checks.size(), str(metrics)])
	for failure in failures: printerr("FAIL: " + failure)
	game.get_tree().quit(0 if failures.is_empty() else 1)
