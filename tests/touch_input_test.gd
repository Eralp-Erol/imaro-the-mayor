extends RefCounted
## Desktop engine event tests, not physical iPad verification.
var game: Node3D
var checks: Array[String] = []
var failures: Array[String] = []
var taps: Array[Vector2] = []
var samples: Array[Dictionary] = []

func frames(count: int = 3) -> void:
	for i in range(count): await game.get_tree().process_frame

func check(ok: bool, text: String) -> void:
	checks.append(text)
	if not ok: failures.append(text)

func send(event: InputEvent) -> void:
	# Platform route: convert logical coordinates back to window pixels before parsing.
	# Goes through Input before viewport dispatch; mouse emulation stays disabled.
	Input.parse_input_event(event.xformed_by(game.get_viewport().get_screen_transform()))
	await frames()

func touch(index: int, at: Vector2, down: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	event.canceled = canceled
	await send(event)

func tap(at: Vector2) -> void:
	await touch(0, at, true)
	await touch(0, at, false)

func drag(index: int, from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to
	event.relative = to - from
	await send(event)

func run(application: Node3D) -> void:
	game = application
	game.rig.parcel_tapped.connect(func(at: Vector2): taps.append(at))
	await frames(12)
	for window_size in [Vector2i(1024, 768), Vector2i(1180, 820), Vector2i(1366, 1024)]:
		game.get_window().size = window_size
		await frames(10)
		game.rig.focus(Vector3(-8, 0, 2), false)
		await game.get_tree().create_timer(0.3).timeout
		game.select_parcel(19)
		game.hud.panel.hide()
		taps.clear()
		var p: CityModel.Parcel = game.sim.parcels[23]
		var at: Vector2 = game.rig.camera.unproject_position(Vector3(p.geometry.x, 0.6, p.geometry.z))
		await tap(at)
		check(game.hud.selected == 23 and taps.size() == 1 and game.hud.panel.visible, "%s: pencere → viewport → tek parsel dokunuşu" % window_size)
		var target: Rect2 = game.hud.propose_button.get_global_rect()
		var screen_transform: Transform2D = game.get_viewport().get_screen_transform()
		var screen_target: Rect2 = screen_transform * target
		check(screen_target.size.y >= 44, "%s: birincil düğme en az 44 ekran birimi" % window_size)
		check(game.get_viewport().get_visible_rect().encloses(target), "%s: imar düğmesi görünür alan içinde" % window_size)
		samples.append({"window": str(window_size), "viewport": str(game.get_viewport().get_visible_rect().size), "primary_target_pixels": str(screen_target.size)})
	# Native touch must activate the standard Control exactly once, with no world gesture.
	game.select_parcel(23)
	taps.clear()
	var initial_cash: int = game.sim.municipality.cash
	await tap(game.hud.propose_button.get_global_rect().get_center())
	check(game.sim.pending_for(23) and game.sim.municipality.cash == initial_cash - 1000, "Native dokunma HUD üzerinden tek imar teklifi gönderir")
	check(taps.is_empty() and game.rig.touches.is_empty(), "HUD dokunuşu dünya seçimine veya takılı parmağa dönüşmez")
	game.hud.panel.hide()
	taps.clear()
	var before: Vector3 = game.rig.target
	await touch(4, Vector2(350, 350), true)
	await drag(4, Vector2(350, 350), Vector2(430, 385))
	await touch(4, Vector2(430, 385), false)
	check(game.rig.target.distance_to(before) > 1 and taps.is_empty(), "Tek parmak sürükleme pan yapar; seçim üretmez")
	taps.clear()
	var old_zoom: float = game.rig.desired_zoom
	var old_yaw: float = game.rig.yaw
	await touch(2, Vector2(350, 350), true)
	await touch(7, Vector2(500, 350), true)
	await drag(7, Vector2(500, 350), Vector2(560, 390))
	await touch(7, Vector2(560, 390), false)
	await touch(2, Vector2(350, 350), false)
	check(game.rig.desired_zoom < old_zoom and game.rig.yaw != old_yaw and taps.is_empty(), "İki farklı parmak kimliği pinch/dönüş yapar; seçim üretmez")
	taps.clear()
	await touch(3, Vector2(400, 350), true)
	await touch(3, Vector2(400, 350), false, true)
	check(taps.is_empty() and game.rig.touches.is_empty(), "İptal edilen dokunuş seçim yapmadan temizlenir")
	game.select_parcel(23)
	await touch(5, Vector2(400, 350), true)
	await drag(5, Vector2(400, 350), Vector2(1100, 350))
	await touch(5, Vector2(1100, 350), false)
	check(game.rig.touches.is_empty(), "Dünyada başlayıp panel üzerinde biten parmak takılı kalmaz")
	game.hud.panel.hide()
	await touch(6, Vector2(400, 350), true)
	game.rig.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(game.rig.touches.is_empty() and not game.rig.pressed, "Odak kaybı etkin jestleri temizler")
	await touch(6, Vector2(400, 350), false, true)
	DirAccess.make_dir_recursive_absolute("res://artifacts/tests")
	var file := FileAccess.open("res://artifacts/tests/touch-input.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "screens": samples,
		"input_route": "Input.parse_input_event, logical-to-window transformed", "physical_ipad_tested": false}, "\t"))
	file.close()
	print("TOUCH_INPUT: %d/%d passed" % [checks.size() - failures.size(), checks.size()])
	for failure in failures: printerr("FAIL: " + failure)
	game.get_tree().quit(0 if failures.is_empty() else 1)
