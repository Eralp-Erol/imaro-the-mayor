extends SceneTree
## T-050 veri keşfi (salt okunur): gerçek playable üzerinde sim parsel/ekonomi okumalarının biçimi ve maliyeti.
## Başsız:  tools/godot.sh --headless --path . --script res://tools/godot/life_data_probe.gd
## Çıktı satırları: LIFEDATA_*. Sim'e YAZMAZ (yalnız okuma sorguları ve `advance` ile zaten var olan tick sürücüsü).

const SCENE := "res://scenes/game/playable.tscn"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var packed: PackedScene = load(SCENE)
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.set_process(false)
	var facade: SimFacade = scene._facade
	var net: WorldNetwork = scene._net
	if facade == null or net == null:
		push_error("probe: facade/net yok")
		quit(2)
		return
	print("LIFEDATA_NET ", JSON.stringify(net.counts()))
	var f0 := facade.parcel_changes_since(-1)
	print("LIFEDATA_FEED_INIT complete=%s n=%d epoch=%d up_to=%d" % [str(f0.complete), f0.ids.size(), f0.epoch, f0.up_to_tick])
	facade.advance(1)
	var f1 := facade.parcel_changes_since(0)
	print("LIFEDATA_FEED_T1 complete=%s n=%d epoch=%d up_to=%d" % [str(f1.complete), f1.ids.size(), f1.epoch, f1.up_to_tick])
	var t_s := Time.get_ticks_usec()
	var sample := PackedInt64Array()
	for i in 400:
		sample.append(facade.parcel_ids()[i] if i == 0 else int(i * 90 + 1))
	var vv := facade.parcel_views(sample)
	print("LIFEDATA_VIEW_COST n=%d ms=%.2f" % [vv.size(), (Time.get_ticks_usec() - t_s) / 1000.0])
	t_s = Time.get_ticks_usec()
	vv = facade.parcel_views(sample)
	print("LIFEDATA_VIEW_COST_2 n=%d ms=%.2f" % [vv.size(), (Time.get_ticks_usec() - t_s) / 1000.0])
	for step in [0]:
		if step > 0:
			facade.advance(step)
		var t0 := Time.get_ticks_usec()
		var out := facade.economy_outcome()
		var t_out := (Time.get_ticks_usec() - t0) / 1000.0
		var rows := []
		for r in out.regions:
			rows.append(r.to_dict())
		print("LIFEDATA_OUTCOME tick=%d ms=%.2f available=%s %s" % [facade.current_tick(), t_out, str(out.available),
				JSON.stringify(rows)])
		t0 = Time.get_ticks_usec()
		var ids := facade.parcel_ids()
		var views := facade.parcel_views(ids)
		var t_p := (Time.get_ticks_usec() - t0) / 1000.0
		var by_dev := {}
		var by_use := {}
		var units_sum := 0
		var units_max := 0
		for v in views:
			by_dev[String(v.development)] = int(by_dev.get(String(v.development), 0)) + 1
			by_use[String(v.use)] = int(by_use.get(String(v.use), 0)) + 1
			units_sum += v.units
			units_max = maxi(units_max, v.units)
		print("LIFEDATA_PARCELS tick=%d n=%d read_ms=%.2f dev=%s use=%s units_sum=%d units_max=%d" % [
				facade.current_tick(), ids.size(), t_p, JSON.stringify(by_dev), JSON.stringify(by_use), units_sum,
				units_max])
		var t1 := Time.get_ticks_usec()
		var feed := facade.parcel_changes_since(facade.current_tick())
		print("LIFEDATA_FEED complete=%s n=%d ms=%.3f" % [str(feed.complete), feed.ids.size(),
				(Time.get_ticks_usec() - t1) / 1000.0])
	# Kenar başına cephe parsel sayıları ve birim toplamları (dağılım).
	var ids2 := facade.parcel_ids()
	var view_by: Dictionary = {}
	for v in facade.parcel_views(ids2):
		view_by[v.id] = v
	var per_edge: Array[int] = []
	var by_class := {}
	var matched := 0
	for eid in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != &"road":
			continue
		var u := 0
		var pcount := 0
		for pid in net.edge_parcels(eid):
			var v: ParcelView = view_by.get(int(pid))
			if v != null:
				matched += 1
				u += v.units
			pcount += 1
		var key := String(e.road_class)
		if not by_class.has(key):
			by_class[key] = {"n": 0, "len": 0.0, "units": 0, "parcels": 0}
		by_class[key]["n"] += 1
		by_class[key]["len"] += e.length
		by_class[key]["units"] += u
		by_class[key]["parcels"] += pcount
		per_edge.append(u)
	per_edge.sort()
	print("LIFEDATA_EDGES by_class=%s matched_parcels=%d units_p50=%d p90=%d max=%d" % [JSON.stringify(by_class),
			matched, per_edge[per_edge.size() / 2], per_edge[int(per_edge.size() * 0.9)], per_edge[-1]])
	quit(0)
