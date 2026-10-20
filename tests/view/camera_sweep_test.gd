extends GdUnitTestSuite
## T-003 ölçüt 7 (yol tanımı) · Otomatik tarama: metro -> ilçe -> sokak -> ilçe -> metro, kareye bağlı, sürekli, veri
## türevli. Ölçümün kendisi (kare süresi, draw call) pencereli çalışır: tools/perf.sh (bkz T-003 kanıtı).

var _world: WorldData
var _ground: Callable


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())
	_ground = func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level)


func test_sweep_starts_and_ends_at_metro_scale_and_reaches_street_scale_in_the_middle() -> void:
	var sweep := CameraSweep.build(_world, "street:port", _ground, 100, 10)
	assert_int(sweep.total_frames()).is_equal(10 + 4 * 100)
	assert_float(sweep.state_at_frame(0).distance).is_greater(50000.0)
	assert_float(sweep.state_at_frame(sweep.total_frames()).distance).is_greater(50000.0)
	var lowest := INF
	var saw: Dictionary = {}
	for f in range(0, sweep.total_frames() + 1):
		var d := sweep.state_at_frame(f).distance
		lowest = minf(lowest, d)
		saw[CameraSweep.phase_of(d)] = true
	assert_float(lowest).is_less_equal(CameraPresets.STREET_DISTANCE_M + 0.01)
	for phase in [&"metro", &"district", &"local", &"street"]:
		assert_bool(saw.has(phase)).is_true()


func test_sweep_motion_is_continuous_no_gates_no_teleports() -> void:
	var sweep := CameraSweep.build(_world, "street:port", _ground, 120, 0)
	var prev := sweep.state_at_frame(0)
	for f in range(1, sweep.total_frames() + 1):
		var cur := sweep.state_at_frame(f)
		assert_float(maxf(cur.distance, prev.distance) / minf(cur.distance, prev.distance)).is_less(1.12)
		# Yer değiştirme, o andaki uzaklığın küçük bir kesri (ekranda sıçrama yok).
		assert_float(Vector2(cur.focus_x - prev.focus_x, cur.focus_z - prev.focus_z).length()) \
				.is_less(cur.distance * 0.2 + 5.0)
		assert_float(absf(CameraState.angle_delta_deg(prev.heading_deg, cur.heading_deg))).is_less(3.0)
		prev = cur


func test_sweep_orbits_the_heading_and_every_frame_state_is_valid_and_on_the_ground() -> void:
	var sweep := CameraSweep.build(_world, "street:port", _ground, 60, 0)
	var headings: Array[float] = []
	for f in range(0, sweep.total_frames() + 1, 15):
		var s := sweep.state_at_frame(f)
		assert_bool(s.is_valid()).is_true()
		assert_float(s.focus_y).is_equal_approx(maxf(_world.height_at(s.focus_x, s.focus_z), _world.sea_level), 0.01)
		headings.append(s.heading_deg)
	var spread := 0.0
	for h in headings:
		spread = maxf(spread, absf(CameraState.angle_delta_deg(headings[0], h)))
	assert_float(spread).is_greater(60.0)  # yalnız zoom değil, yörünge de


func test_sweep_follows_the_data_and_unresolvable_street_degrades_to_a_metro_hold() -> void:
	var moved := WorldTestSupport.coarse(WorldTestSupport.control())
	moved.port_site.position += Vector2(1500.0, -900.0)
	var a := CameraSweep.build(_world, "street:port", _ground, 60, 0).state_at_frame(120)
	var b := CameraSweep.build(moved, "street:port", _ground, 60, 0).state_at_frame(120)
	assert_float(Vector2(a.focus_x - b.focus_x, a.focus_z - b.focus_z).length()).is_greater(500.0)
	var bad := CameraSweep.build(_world, "street:nowhere", _ground, 60, 0)
	assert_int(bad.keys.size()).is_equal(2)
	assert_float(bad.state_at_frame(30).distance).is_greater(50000.0)


func test_phase_labels_partition_the_distance_range() -> void:
	assert_str(String(CameraSweep.phase_of(58000.0))).is_equal("metro")
	assert_str(String(CameraSweep.phase_of(10000.0))).is_equal("district")
	assert_str(String(CameraSweep.phase_of(1000.0))).is_equal("local")
	assert_str(String(CameraSweep.phase_of(60.0))).is_equal("street")
