extends Node3D

var district := DistrictView.new()
var rig := CityCamera.new()
var sun := DirectionalLight3D.new()
var environment := WorldEnvironment.new()
var sim := CitySimulation.new()
var clock := GameClock.new()
var hud := MayorHUD.new()
var cloudy := false
var capture_runner: RefCounted

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b8cfd2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8e5e5")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = env
	add_child(environment)
	sun.rotation_degrees = Vector3(-50, -28, 0)
	sun.light_color = Color("fff3d8")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200
	add_child(sun)
	add_child(district)
	var visuals: Array[Dictionary] = []
	for parcel in sim.parcels: visuals.append(sim.visual_data(parcel))
	district.build(visuals)
	add_child(rig)
	rig.parcel_tapped.connect(func(screen: Vector2): select_parcel(district.pick_ray(rig.camera, screen)))
	hud.sim = sim
	hud.clock = clock
	add_child(hud)
	hud.parcel_requested.connect(select_parcel)
	hud.camera_command.connect(camera_action)
	hud.weather_requested.connect(toggle_weather)
	hud.save_requested.connect(save_game)
	hud.load_requested.connect(load_game)
	sim.parcel_changed.connect(update_parcel)
	sim.changed.connect(on_day_changed)
	select_parcel(23)
	if "--visual-capture" in OS.get_cmdline_user_args():
		hud.hide()
		capture_visuals.call_deferred()
	if "--capture-gameplay" in OS.get_cmdline_user_args():
		capture_runner = load("res://tests/gameplay_capture.gd").new()
		capture_runner.run.call_deferred(self)
	if "--test-touch" in OS.get_cmdline_user_args():
		capture_runner = load("res://tests/touch_input_test.gd").new()
		capture_runner.run.call_deferred(self)

func _process(delta: float) -> void:
	clock.advance(delta, sim)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		hud.set_speed(1 if clock.speed == 0 else 0)

func select_parcel(id: int) -> void:
	if id < 0: return
	district.select(id)
	hud.select_parcel(id)

func update_parcel(id: int) -> void:
	district.update_parcel(sim.visual_data(sim.parcels[id]))

func on_day_changed() -> void:
	if not sim.events.is_empty(): hud.status.text = sim.events.back().title

func camera_action(command: String) -> void:
	match command:
		"in": rig.desired_zoom = maxf(28, rig.desired_zoom / 1.2)
		"out": rig.desired_zoom = minf(135, rig.desired_zoom * 1.2)
		"left": rig.rotate_view(-1)
		"right": rig.rotate_view(1)
		"home": rig.focus(Vector3(-8, 0, 2), false)
		"focus":
			if hud.selected >= 0:
				var p := sim.parcels[hud.selected]
				rig.focus(Vector3(p.geometry.x + 9, 0, p.geometry.z))

func toggle_weather() -> void:
	cloudy = not cloudy
	sun.light_energy = 0.35 if cloudy else 0.8
	sun.light_color = Color("dce7ed") if cloudy else Color("fff3d8")
	environment.environment.ambient_light_energy = 0.5 if cloudy else 0.35
	hud.show_status("Bulutlu görünüm" if cloudy else "Açık hava görünümü")

func save_game() -> void:
	hud.show_status("Oyun kaydedildi." if CitySave.save_game(sim) == OK else "Kayıt yazılamadı.")

func load_game() -> void:
	var restored := CitySave.load_game()
	if restored == null:
		hud.show_status("Geçerli kayıt bulunamadı.")
		return
	sim.changed.disconnect(hud.refresh)
	sim.changed.disconnect(on_day_changed)
	sim.parcel_changed.disconnect(update_parcel)
	sim = restored
	clock.speed = 0
	clock.accumulator = 0
	hud.sim = sim
	sim.changed.connect(hud.refresh)
	sim.changed.connect(on_day_changed)
	sim.parcel_changed.connect(update_parcel)
	for p in sim.parcels: update_parcel(p.id)
	hud.show_status("Kayıt yüklendi. Zaman duraklatıldı.")

func capture_visuals() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/screenshots")
	await get_tree().create_timer(1.0).timeout
	RenderingServer.force_draw.call_deferred()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/screenshots/01-world-gate.png")
	rig.focus(Vector3(-22, 0, 21))
	rig.yaw = 0.25
	await get_tree().create_timer(1.0).timeout
	RenderingServer.force_draw.call_deferred()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://artifacts/screenshots/02-neighborhood-gate.png")
	print("VISUAL_CAPTURE_COMPLETE")
	get_tree().quit()
