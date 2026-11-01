# gdlint:disable=max-line-length
extends RefCounted
## QA 2026-11-01 · gerçek-dünya probe ortak kurulumu (test paketi DEĞİL; probe dosyaları `preload` eder).
## `tests/sim/perf/council_real_probe.gd` + `expropriation_reaction_real_probe.gd` kurulumunun parametrik hali:
## gerçek dünya (verilen tohum) + ağ + T0 yerleşimi + `PlayableEconomy` + `PlayablePolitics` (`data/game/playable_*.json`
## + `data/politics/reactions.json`) + yol komutları + GERÇEK kamulaştırma köprüsü (`PlayableExpropriation.attach_port`,
## oyunun `PlayableRoads.attach_commands` ile AYNI çağrı) + gösterge bütçe. `SimBuildingProjector` TAKILMAZ (görünüm tarafı;
## sim durumunu değiştirmez, TEK-01). Oyun/sim kodu değişmez.

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const WARM_DAYS := 30


## Bir dünya tohumunun pahalı kısmı (≈90 sn): bir kez kurulur, birden çok sim senaryosu paylaşır. Ağ yol komutlarıyla
## değişir; her senaryo sonunda `restore_net` ile taban grafına döndürülür (hash doğrulanır).
class WorldCtx:
	extends RefCounted
	var world_seed: int = 0
	var control: Dictionary = {}
	var world: WorldData = null
	var net_control: Dictionary = {}
	var net: WorldNetwork = null
	var settlement: SettlementResult = null
	var views: Array[ParcelView] = []
	var road_rules: RoadDraftRules = null
	var base_hash: String = ""
	var game_jurisdiction: Array[StringName] = []
	var region_of_parcel: Dictionary = {}
	var regions: Dictionary = {}

	## `all` true = yetki alanı kısıtı yok (NE-OLUR: başka başlangıç bölgesi, CAN-08); false = oyunun verisi (`["D2"]`).
	func set_jurisdiction_all(all: bool) -> void:
		var empty: Array[StringName] = []
		road_rules.jurisdiction_regions = empty if all else game_jurisdiction.duplicate()

	## Senaryo sonrası: oyuncu yollarını geri al (LIFO) ve ağın taban graf özetine döndüğünü doğrula.
	func restore_net(ctx: PublicWorksContext, work_count: int) -> bool:
		for _i in work_count:
			var undone := ctx.undo_live_op()
			if not bool(undone["ok"]):
				return false
		return net.graph_hash() == base_hash


## Bir senaryonun sim'i: taze sim + gerçek bağlama.
class SimCtx:
	extends RefCounted
	var handle: PoliticsHandle = null
	var facade: SimFacadeImpl = null
	var ctx: PublicWorksContext = null
	var cfg: EconomyConfig = null
	var pol_cfg: PoliticsConfig = null
	var seen_event_seq: int = 0
	var counts: Dictionary = {}
	var kinds: Dictionary = {}
	var group_reacted: Array = []
	var pol_events: Array = []
	var agenda_seen: Dictionary = {}
	var road_events: Array = []
	var event_samples: Dictionary = {}

	func step(days: int = 1) -> void:
		for _d in days:
			facade.advance(1)
			for e in facade.events_since(seen_event_seq):
				seen_event_seq = maxi(seen_event_seq, e.seq)
				var key := String(e.message_key)
				counts[key] = int(counts.get(key, 0)) + 1
				if not event_samples.has(key):
					event_samples[key] = e
				kinds[String(e.kind)] = int(kinds.get(String(e.kind), 0)) + 1
				if String(e.kind) == "group.reacted":
					group_reacted.append([e.tick, str(e.args.get("topic", "")), int(e.args.get("intensity", 0))])
				if String(e.kind).begins_with("politics.") or key == "event.media.published":
					pol_events.append([e.tick, String(e.kind), key])
				if key.begins_with("event.road."):
					road_events.append([e.tick, key])
			for it in facade.agenda_items():
				if not agenda_seen.has(it.item_id):
					agenda_seen[it.item_id] = {"id": it.item_id, "template": String(it.template_id), "opened": it.opened_tick,
						"deadline": it.deadline_tick, "region": String(it.region_code), "title_key": String(it.title_key),
						"cause_refs": Array(it.cause_refs).map(func(x: Variant) -> String: return str(x)),
						"reason_ids": Array(it.reason_ids), "args": SimContract.to_args(it.args)}
				agenda_seen[it.item_id]["status_last"] = String(it.status)

	func tick() -> int:
		return facade.current_tick()

	## Tüm bölgelerde konutlu hane toplamı (gerçek sim istatistiği).
	func housed_total() -> int:
		var total := 0
		for row in EconomyQuery.region_stats(facade.game_state(), cfg):
			total += int(row["housed_hh"])
		return total

	func region_stat(code: String, field: String) -> int:
		for row in EconomyQuery.region_stats(facade.game_state(), cfg):
			if String(row["code"]) == code:
				return int(row[field])
		return -1

	## Tepki defteri: {bölge: [[tick, hane, komut]...]} (yerinden edilen).
	func displaced_book() -> Dictionary:
		var out := {}
		var book: Dictionary = PublicWorksState.data(facade.game_state()).get("displaced", {})
		for code: String in book:
			out[code] = (book[code] as Array).duplicate(true)
		return out

	## Gündem öğeleri (durum dahil, kapalılar da): sim durumundan.
	func agenda_all() -> Array:
		return (PoliticsState.data(facade.game_state())["events"]["agenda"] as Array).duplicate(true)


static func build_world(world_seed: int) -> WorldCtx:
	var w := WorldCtx.new()
	w.world_seed = world_seed
	w.control = WorldControlData.load_dir(DATA_DIR)
	w.world = WorldGenerator.generate(w.control, world_seed, {})
	w.net_control = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	w.net = NetworkGenerator.generate(w.world, w.net_control, world_seed)
	var loaded := SettlementTable.load_game_table()
	w.settlement = T0Settlement.generate_detailed(w.world, w.net, loaded["table"], world_seed, rules)
	w.views = _views(w.net)
	for v in w.views:
		w.region_of_parcel[v.id] = String(v.region_code)
		w.regions[String(v.region_code)] = int(w.regions.get(String(v.region_code), 0)) + 1
	w.road_rules = RoadDraftRules.load_path(NETWORK_PATH)
	w.game_jurisdiction = w.road_rules.jurisdiction_regions.duplicate()
	w.base_hash = w.net.graph_hash()
	return w


## Taze sim (aynı dünya ağı). `expropriation`: gerçek köprü + korunan T0 kümesi (oyunun bağı). `sim_seed` -1 = dünya tohumu.
static func new_sim(w: WorldCtx, sim_seed: int = -1, expropriation: bool = true) -> SimCtx:
	var s := SimCtx.new()
	var seed_value := w.world_seed if sim_seed < 0 else sim_seed
	var source := ListParcelSource.create(&"ismeral", w.views)
	var stock := PlayableStock.from_columns(w.settlement.columns)
	s.cfg = PlayableEconomy.config_for(w.views, stock, {"decision": {"priority_review_enabled": 1}})
	s.pol_cfg = PlayablePolitics.config()
	s.handle = PoliticsBootstrap.create(seed_value, source, s.cfg, stock, null, s.pol_cfg)
	if s.handle == null:
		return null
	s.facade = s.handle.facade as SimFacadeImpl
	s.ctx = PublicWorksContext.create(w.net, w.road_rules, PublicWorksConfig.load_default())
	if expropriation:
		PlayableExpropriation.attach_port(s.ctx, w.net, w.road_rules, w.settlement.columns)
	if not s.facade.attach_public_works(s.ctx):
		return null
	PlayableBudget.attach(s.facade, true)
	return s


static func points_cm(pts: PackedVector2Array) -> PackedInt64Array:
	var cm := PackedInt64Array()
	for p in pts:
		cm.append(roundi(p.x * 100.0))
		cm.append(roundi(p.y * 100.0))
	return cm


## Bölgede rastgele yol adayları (60-250 m, düz doğru, kenardan başlar). Sim önizlemesi (`expropriate: true`) geçerli ve
## en az 1 parsel alıyorsa listeye girer. Satır: {cm, pts, len, order, taken, built, hh, near_hh, regions_taken}.
static func region_candidates(w: WorldCtx, s: SimCtx, region: String, pool: int, stream: String, tally: Dictionary = {}) -> Array:
	var ids: Array = w.net.edges.keys()
	ids.sort()
	var in_region: Array = []
	for eid: int in ids:
		var e: WorldRoadEdge = w.net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var mid := (w.net.node_pos(e.a) + w.net.node_pos(e.b)) * 0.5
		if String(w.net.rules.region_code_at(w.world, mid)) == region:
			in_region.append(eid)
	var out: Array = []
	tally["edges_in_region"] = in_region.size()
	if in_region.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(w.world_seed, stream)
	for n in pool:
		var e: WorldRoadEdge = w.net.edges[in_region[rng.randi() % in_region.size()]]
		var a := w.net.node_pos(e.a).lerp(w.net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var row := candidate_for(w, s, PackedVector2Array([a, b]), tally)
		if not row.is_empty():
			row["order"] = n
			out.append(row)
	return out


## Verilen çizgi için kamulaştırmalı önizleme satırı; geçersiz ya da parsel almıyorsa {}.
static func candidate_for(w: WorldCtx, s: SimCtx, pts: PackedVector2Array, tally: Dictionary = {}) -> Dictionary:
	var plain := RoadDraftCheck.check(w.net, pts, RoadDrawTool.ROAD_CLASS, w.road_rules)
	var checked: PackedVector2Array = plain.get("points", pts)
	var cm := points_cm(checked)
	var v := s.facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	if v.status != CommandResult.STATUS_VALID or int(v.args.get("taken_parcels", 0)) <= 0:
		var why := "valid_no_parcels" if v.status == CommandResult.STATUS_VALID else String(v.reason_key)
		tally[why] = int(tally.get(why, 0)) + 1
		return {}
	var taken := RoadDraftCheck.taken_parcels(w.net, checked, RoadDrawTool.ROAD_CLASS)
	var regions_taken := {}
	for pid in taken:
		var code := String(w.region_of_parcel.get(int(pid), "?"))
		regions_taken[code] = int(regions_taken.get(code, 0)) + 1
	return {"cm": cm, "pts": checked, "len": float(plain.get("length_m", 0.0)), "order": 0,
		"taken": int(v.args.get("taken_parcels", 0)), "built": int(v.args.get("taken_built_parcels", 0)),
		"hh": int(v.args.get("displaced_households", 0)), "near_hh": int(v.args.get("nearby_households", 0)),
		"regions_taken": regions_taken}


static func _views(net: WorldNetwork) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var src: Variant = net.parcels
	var items: Array = src.values() if src is Dictionary else Array(src)
	for item in items:
		var wp := item as WorldParcel
		if wp == null or wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"
		out.append(v)
	return out
