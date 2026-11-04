extends RefCounted
## QA (T-040) yardımcı: gerçek Ismeral dünyası + T0 + PlayableEconomy + PoliticsBootstrap (playable.gd ile aynı kurulum).

static var _cache: Dictionary = {}


static func base() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var control := WorldControlData.load_dir("res://data/world/ismeral")
	var seed := int(control["world"]["default_seed"])
	var world := WorldGenerator.generate(control, seed, {})
	var net_control: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/ismeral/network.json"))
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/ismeral/settlement.json"))
	var net := NetworkGenerator.generate(world, net_control, seed)
	var lib := KitLibrary.load_manifest()
	var settlement := T0Settlement.generate_detailed(world, net, lib.manifest, seed, rules)
	var views: Array[ParcelView] = []
	for item in net.parcels.values():
		var wp := item as WorldParcel
		if wp == null or wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"
		views.append(v)
	var t0 := {}
	for pid in settlement.columns.occupied_parcels():
		t0[int(pid)] = true
	_cache = {"seed": seed, "world": world, "net": net, "settlement": settlement, "views": views,
			"stock": PlayableStock.from_columns(settlement.columns), "t0": t0}
	return _cache


static func handle(patch: Dictionary = {}, sim_seed: int = -1) -> PoliticsHandle:
	var b := base()
	var source := ListParcelSource.create(&"ismeral", b["views"])
	var cfg := PlayableEconomy.config_for(b["views"], b["stock"], patch)
	return PoliticsBootstrap.create(b["seed"] if sim_seed == -1 else sim_seed, source, cfg, b["stock"])


static func projector(f: SimFacade) -> SimBuildingProjector:
	var b := base()
	return SimBuildingProjector.create(f, b["settlement"], SimBuildingMapping.load_default(), b["seed"])


## Tam tarama gerçeği: projector kuralıyla yapı olması gereken parseller -> development.
static func truth(f: SimFacade, placer: SimBuildingPlacer) -> Dictionary:
	var b := base()
	var t0: Dictionary = b["t0"]
	var ids := PackedInt64Array()
	for pid in f.parcel_ids():
		ids.append(int(pid))
	var out := {"build": {}, "uc": 0, "built": 0, "stalled": 0, "planned": 0, "unplaceable": 0, "t0_by_sim": 0,
			"t0_stage": {}}
	var i := 0
	while i < ids.size():
		var chunk := ids.slice(i, mini(i + 500, ids.size()))
		i += chunk.size()
		for v in f.parcel_views(chunk):
			if t0.has(v.id):
				out["t0_stage"][String(v.development)] = int(out["t0_stage"].get(String(v.development), 0)) + 1
				if v.developed_by_sim:
					out["t0_by_sim"] += 1
				else:
					continue
			if not v.developed_by_sim:
				continue
			if v.development == ParcelView.DEVELOPMENT_PLANNED:
				out["planned"] += 1
			var building := v.use != ParcelView.USE_NONE and v.units > 0 and v.development in [
					ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT,
					ParcelView.DEVELOPMENT_STALLED]
			if not building:
				continue
			match v.development:
				ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
					out["uc"] += 1
				ParcelView.DEVELOPMENT_BUILT:
					out["built"] += 1
				_:
					out["stalled"] += 1
			if placer.plan(v.id, v.use, v.units) == null:
				out["unplaceable"] += 1
				continue
			out["build"][v.id] = String(v.development)
	return out
