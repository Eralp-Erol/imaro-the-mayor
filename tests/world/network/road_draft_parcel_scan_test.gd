extends GdUnitTestSuite
## T-051 · RoadDraftCheck.first_parcel_hit ön eleme (RoadDraftParcelScan) özgün (önbelleksiz/ön elemesiz) algoritmayla
## BİREBİR aynı sonucu verir ({found, at}): el yapımı parselli ızgarada ve hafif Ismeral ağında rastgele taslaklar
## (bloğa giren, yol şeridinden geçen, açık arazide kalan). Referans = ön elemeden önceki işlev (testte kopyası).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL


## Ön elemeden ÖNCEki `first_parcel_hit` (aynen).
func _reference(net: WorldNetwork, pts: PackedVector2Array, rules: RoadDraftRules, half_width_m: float) -> Dictionary:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var normal := Vector2(-d.y, d.x).normalized() * half_width_m
		var steps := maxi(1, int(ceil(d.length() / rules.parcel_sample_step_m)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			for probe in [p, p + normal, p - normal]:
				if RoadDraftCheck._in_parcelized_block(net, probe):
					return {"found": true, "at": probe}
	return {"found": false, "at": Vector2.ZERO}


func _compare(net: WorldNetwork, pts: PackedVector2Array, rules: RoadDraftRules, half_width: float,
		label: String) -> bool:
	var want := _reference(net, pts, rules, half_width)
	var got := RoadDraftCheck.first_parcel_hit(net, pts, rules, half_width)
	assert_bool(got["found"] == want["found"]).override_failure_message("found %s" % label).is_true()
	assert_bool(got["at"] == want["at"]).override_failure_message(
			"at %s: %s != %s" % [label, got["at"], want["at"]]).is_true()
	return bool(want["found"])


func test_scan_matches_reference_on_a_parcelled_grid() -> void:
	var net := NetworkTestSupport.grid_network(NetworkTestSupport.flat_world(3000.0), 3, 3, DX, DZ, ORIGIN, 7,
			NetworkTestSupport.KEEP_PARCELS)
	var rules := RoadDraftRules.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	var found := 0
	var clear := 0
	for n in 120:
		var a := Vector2(rng.randf_range(380.0, 1100.0), rng.randf_range(380.0, 900.0))
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 250.0)
		var pts := PackedVector2Array([a, b]) if n % 3 != 0 else PackedVector2Array([a, a.lerp(b, 0.5), b])
		if _compare(net, pts, rules, 5.0, "ızgara %d" % n):
			found += 1
		else:
			clear += 1
	assert_int(found).override_failure_message("parselli bloğa giren taslak üretilmedi").is_greater(10)
	assert_int(clear).override_failure_message("temiz taslak üretilmedi").is_greater(10)
	# Tek noktalı taslak ve sıfır uzunluk.
	_compare(net, PackedVector2Array([Vector2(700, 550)]), rules, 5.0, "tek nokta")
	_compare(net, PackedVector2Array([Vector2(700, 550), Vector2(700, 550)]), rules, 5.0, "sıfır uzunluk")


func test_scan_matches_reference_on_the_light_ismeral_network() -> void:
	var net := NetworkTestSupport.light_network()
	var rules := RoadDraftRules.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 52
	var ids: Array = net.edges.keys()
	ids.sort()
	var found := 0
	for n in 150:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30.0, 300.0)
		if _compare(net, PackedVector2Array([a, b]), rules, net.rules.width_of(LOCAL) * 0.5, "ismeral %d" % n):
			found += 1
	assert_int(found).override_failure_message("parselli bloğa giren taslak üretilmedi").is_greater(0)


func test_check_result_is_unchanged_for_scan_hits_and_misses() -> void:
	var net := NetworkTestSupport.grid_network(NetworkTestSupport.flat_world(3000.0), 3, 3, DX, DZ, ORIGIN, 7,
			NetworkTestSupport.KEEP_PARCELS)
	var rules := RoadDraftRules.new()
	var into_block := RoadDraftCheck.check(net, PackedVector2Array([Vector2(580, 550), Vector2(580, 650)]), LOCAL, rules)
	assert_str(String(into_block["reason"])).is_equal("crosses_parcels")
	var open_land := RoadDraftCheck.check(net, PackedVector2Array([Vector2(580, 500), Vector2(580, 400)]), LOCAL, rules)
	assert_bool(open_land["ok"]).override_failure_message(str(open_land)).is_true()


func test_blocks_reachable_only_by_the_side_probes_are_not_missed() -> void:
	# Taslak ızgaranın 20 m dışından yatay gider (kutusu bloğa değmez); yalnız yan örnekler (±30 m) bloğa girer.
	var net := NetworkTestSupport.grid_network(NetworkTestSupport.flat_world(3000.0), 3, 3, DX, DZ, ORIGIN, 7,
			NetworkTestSupport.KEEP_PARCELS)
	var rules := RoadDraftRules.new()
	var pts := PackedVector2Array([Vector2(520, 480), Vector2(600, 480)])
	assert_bool(_compare(net, pts, rules, 30.0, "yan örnek")).override_failure_message(
			"referans yan örnekte parselli bloğu bulmalıydı").is_true()
	assert_bool(RoadDraftCheck.first_parcel_hit(net, pts, rules, 30.0)["found"]).is_true()
