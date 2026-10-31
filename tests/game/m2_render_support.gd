class_name M2RenderSupport
extends RefCounted
## T-040 render/oynanabilir testleri ortak yardımcıları (test paketi değildir). Küçük GERÇEK dünya: düz arazi + el
## yapımı ızgara WorldNetwork + gerçek T0Settlement + gerçek PoliticsBootstrap (ekonomi/aktör/siyaset; oynanabilir
## sahneyle aynı kurulum, aynı `PlayableEconomy` başlangıç koşulları) + gerçek SimBuildingProjector. Koordinat gömülü
## değildir: parseller ağdan okunur.

const SEED := 20261020
## Yalnız oyuncunun imar kararı yatırım değerlendirmesini tetikler (periyodik otonom tarama kapalı): nedensellik yalın.
## Bu testler yatırımcı -> projector -> görünüm zincirini sınar, yol-kapasite nedenselliğini DEĞİL (o:
## `playable_infra_capacity_test.gd`): başlangıç boş kapasite mutlak sınırı (`infra_free_units_max`) kapalıdır (-1),
## yani eski %30 pay geçerlidir ve imar önerisi yol olmadan da değerlendirilir.
const NO_INFRA_CAP := {"infra_free_units_max": -1}
const ISOLATE := {"decision": {"review_enabled": 0}, "playable": NO_INFRA_CAP}
## Elverişsiz koşul: dar altyapı + az hane (aynı imar kararı, yatırımcı reddeder; sonuç zorlanmaz).
const UNFAVORABLE := {"regions": {"overrides": {"D1": {"initial_households": 12, "infra_capacity_units": 4}}}}

static var _fx: Dictionary = {}


static func fixture() -> Dictionary:
	if _fx.is_empty():
		var world := NetworkTestSupport.flat_world(3000.0, 100.0)
		var net := NetworkTestSupport.grid_network(world, 14, 8, 120.0, 76.0, Vector2(400.0, 500.0), 7)
		var control := SettlementTestSupport.control()
		control["tower"]["enabled"] = false
		var res := T0Settlement.generate_detailed(world, net, SettlementTestSupport.manifest(), SEED, control)
		var views: Array[ParcelView] = []
		var ids := PackedInt32Array(net.parcels.keys())
		ids.sort()
		for pid in ids:
			var wp: WorldParcel = net.parcels[pid]
			if wp.region_code == &"":
				continue
			var v := ParcelView.new()
			v.id = wp.id
			v.region_code = wp.region_code
			v.center = wp.centroid
			v.area_m2 = int(wp.area)
			v.zone = &"zone.residential"
			views.append(v)
		_fx = {"world": world, "net": net, "settlement": res, "views": views,
				"stock": PlayableStock.from_columns(res.columns)}
	return _fx


## Taze gerçek facade (PoliticsBootstrap). `patch`: ekonomi yapılandırması yaması (ISOLATE/UNFAVORABLE).
static func handle(patch: Dictionary = {}, sim_seed: int = SEED, sim_config: SimConfig = null) -> PoliticsHandle:
	var fx := fixture()
	var source := ListParcelSource.create(&"m2_fixture", fx["views"])
	var tuned := patch if patch.has("playable") else PlayableEconomy._merge(patch, {"playable": NO_INFRA_CAP})
	var cfg := PlayableEconomy.config_for(fx["views"], fx["stock"], tuned)
	var h := PoliticsBootstrap.create(sim_seed, source, cfg, fx["stock"], null, null, sim_config)
	assert(h != null, "PoliticsBootstrap.create başarısız")
	return h


## Küçük gerekçe/olay günlüğü (saklama ufku hızla daralır): gizlenen olay yolunu zorlar.
static func tiny_log_config(capacity: int = 20) -> SimConfig:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim/core_config.json"))
	(raw["sim"] as Dictionary)["reason_log_capacity"] = capacity
	(raw["sim"] as Dictionary)["event_log_capacity"] = capacity
	var cfg := SimConfig.from_dict(raw as Dictionary)
	assert(cfg.is_valid(), "tiny_log_config geçersiz")
	return cfg


static func projector(facade: SimFacade) -> SimBuildingProjector:
	var p := SimBuildingProjector.create(facade, fixture()["settlement"], SimBuildingMapping.load_default(), SEED)
	assert(p != null, "SimBuildingProjector.create başarısız")
	return p


## T0 yapısı olmayan, sim'in vereceği birimle (ekonomi: alan x 6/1000, konut) projector'ın yapı sığdırabildiği ilk
## `count` parsel. `staged`: inşaat başlangıcı ile tamamı farklı kat gösteren (kat kademesi olan) parseller.
## T-062 A2: hero aileleri tek boydur (Studio Director kararı 2) -> tabloda kat kademesi YOKSA (`staging_available`)
## `staged` koşulu boştur ve yerleştirilebilen parseller döner; kademe VARSA koşul aynen uygulanır.
static func free_parcels(proj: SimBuildingProjector, count: int, staged: bool = false) -> PackedInt64Array:
	staged = staged and staging_available()
	var settlement: SettlementResult = fixture()["settlement"]
	var occupied := {}
	for pid in settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	var out := PackedInt64Array()
	for v: ParcelView in fixture()["views"]:
		if out.size() >= count:
			break
		if occupied.has(v.id):
			continue
		var plan := proj.placer().plan(v.id, &"residential", maxi(1, v.area_m2 * 6 / 1000))
		if plan == null:
			continue
		if staged:
			var early := 0
			for r in proj.placer().rows_for(plan, 1):
				early += r.floors
			if early >= plan.floors_total():
				continue
		out.append(v.id)
	return out


## Modül tablosunda aynı ailede (ve aynı zemin-dükkân rolünde) daha az katlı bir modül var mı: inşaat kat kademesi
## (SimBuildingPlacer._stage_module) ancak o zaman görünür.
static func staging_available() -> bool:
	var rules: SettlementRules = (fixture()["settlement"] as SettlementResult).rules
	for m in rules.modules:
		for other in rules.modules:
			if other.family == m.family and other.gf == m.gf and other.floors < m.floors:
				return true
	return false


static func t0_parcels(count: int) -> PackedInt64Array:
	var settlement: SettlementResult = fixture()["settlement"]
	var out := PackedInt64Array()
	for pid in settlement.columns.occupied_parcels():
		if out.size() >= count:
			break
		out.append(int(pid))
	return out


## Parselin projector sütunlarındaki satır dizinleri.
static func rows_of(proj: SimBuildingProjector, parcel_id: int) -> PackedInt32Array:
	var cols := proj.columns()
	var out := PackedInt32Array()
	for i in cols.count:
		if cols.parcel_id[i] == parcel_id:
			out.append(i)
	return out


static func floors_of(proj: SimBuildingProjector, parcel_id: int) -> int:
	var total := 0
	var cols := proj.columns()
	for i in rows_of(proj, parcel_id):
		total += cols.floors[i]
	return total
