extends GdUnitTestSuite
## T-028 ölçüt 6 · harita üç tohumda (3, 77, 1467) çalışır: aynı tohum aynı özet, farklı tohum farklı özet, işaret
## sayıları ve WLD-03 denetimi her tohumda geçerli. Yerleşim, hız için küçültülmüş ağ üzerinde (tam tohum koşusu
## capture'da).

const SEEDS: Array[int] = [3, 77, 1467]

static var _cache: Dictionary = {}


static func _model_for(world_seed: int) -> TopologyModel:
	if not _cache.has(world_seed):
		var world := WorldGenerator.generate(WorldTestSupport.control(), world_seed)
		var net := NetworkGenerator.generate(world, NetworkTestSupport.light_control(), world_seed)
		var result := T0Settlement.generate_detailed(world, net, SettlementTestSupport.manifest(), SettlementTestSupport.SEED,
				SettlementTestSupport.control())
		_cache[world_seed] = TopologyModel.build(world, net, result)
	return _cache[world_seed]


func test_every_seed_builds_a_complete_model_with_matching_counts() -> void:
	for s in SEEDS:
		var m := _model_for(s)
		assert_int(m.regions.size()).override_failure_message("seed %d" % s).is_equal(6)
		assert_int(m.islands.size()).is_equal(m.world.islands.size())
		assert_int(m.sites.size()).is_equal(m.world.sites.size())
		assert_bool(m.has_gulf).is_true()
		assert_bool(m.gap["valid"]).is_true()
		assert_array(m.sites_off_mainland).is_empty()
		assert_array(m.islands_with_forbidden_tags).is_empty()
		assert_int(m.building_total).is_greater(1000)
		var total := 0
		for c in m.density_counts:
			total += c
		assert_int(total).is_equal(m.building_total)


func test_every_seed_projects_with_the_same_north_and_scale() -> void:
	for s in SEEDS:
		var view := TopologyMapView.new()
		view.setup(_model_for(s), false)
		assert_vector(view.projection().north_on_screen()).is_equal_approx(Vector2(0.0, -1.0), Vector2(0.001, 0.001))
		assert_float(view.projection().px_per_m).is_equal_approx(1500.0 / 40000.0, 1.0e-6)
		var stamps := 0
		for l in view.labels():
			stamps += 1 if l["kind"] == &"stamp" else 0
		assert_int(stamps).is_equal(1)
		view.free()


func test_same_seed_same_summary_and_different_seeds_differ() -> void:
	var a := _model_for(3).summary()
	var again := TopologyModel.build(_model_for(3).world, _model_for(3).net, _model_for(3).result).summary()
	assert_dict(again).is_equal(a)
	assert_dict(_model_for(77).summary()).is_not_equal(a)
	assert_dict(_model_for(1467).summary()).is_not_equal(_model_for(77).summary())
