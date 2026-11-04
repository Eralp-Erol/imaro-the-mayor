class_name PublicWorksSupport
extends RefCounted
## T-042 adım 2 test yardımcıları (test paketi değildir). Sentetik düz dünya ikiye bölünür (batı = bölge `A`, doğu =
## bölge
## `B`; kodlar bilerek D1-D6 değildir). Yol ağı: `NetworkTestSupport` ızgarası, iki bölgeye de uzanır. Sim parselleri
## `ListParcelSource` ile ağdan bağımsız kurulur; bağ yalnız bölge kodudur (ekonomi bölge başına kapasite tutar).
## Koordinat gömülü değildir: yol taslakları ızgaranın düğümlerinden türetilir.

const SEED := 20261030
const WORLD_M := 3000.0
const SPLIT_X := 1500.0
## Batı = D1, doğu = D2: ızgara ağ kurallarındaki ayak izi şablonu `D1` bölgesine bağlıdır (NetworkTestSupport); kodu
## yalnız TEST yardımcısı bilir, sim koda gömülü değildir.
const CODE_A := &"D1"
const CODE_B := &"D2"
## Izgara: x çizgileri 1100..1900 (dx 160, 5 sütun), z çizgileri 1100..1400 (dz 100, 3 satır); x = 1500 sınırı geçer.
const GRID_ORIGIN := Vector2(1100.0, 1100.0)
const DX := 160.0
const DZ := 100.0
const COLS := 5
const ROWS := 3
## Dar altyapı + yüksek hane: yatırım isteği var, kapasite VETO (infrastructure_exhausted).
const TIGHT := {"initial_households": 400, "infra_capacity_units": 5}
const PER_REGION := 4
const AREA_M2 := 1800
const ZONE := &"zone.residential"


## Doğu bölgenin kuzeyinde küçük bir göl (su reddi testi).
const LAKE := Rect2(2600.0, 200.0, 300.0, 400.0)


static func two_region_world() -> WorldData:
	var w := NetworkTestSupport.flat_world(WORLD_M, 100.0, LAKE)
	var east := WorldRegion.new()
	east.id = 2
	east.code = CODE_B
	east.anchor = Vector2(2250.0, 1500.0)
	east.radius = Vector2(750.0, 1500.0)
	var west: WorldRegion = w.regions[0]
	west.anchor = Vector2(750.0, 1500.0)
	west.radius = Vector2(750.0, 1500.0)
	w.regions.append(east)
	for j in w.height:
		for i in w.width:
			var idx := j * w.width + i
			if w.land_mask[idx] == 1 and w.cell_to_world(i, j).x >= SPLIT_X:
				w.region_ids[idx] = 2
	return w


## Ağ: ızgara, parselli bloklar, v0 kuralı (yol parsel kümesini değiştirmez).
static func network(world: WorldData = null) -> WorldNetwork:
	var w := world if world != null else two_region_world()
	return NetworkTestSupport.grid_network(w, COLS, ROWS, DX, DZ, GRID_ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)


## Batı (A) ve doğu (B) uçlarından kuzeye çıkan 100 m'lik açık-arazi yolları (cm).
static func spur_a_cm() -> PackedInt64Array:
	return _cm([GRID_ORIGIN, GRID_ORIGIN + Vector2(0, -100)])


static func spur_b_cm() -> PackedInt64Array:
	var east := GRID_ORIGIN + Vector2(DX * COLS, 0)
	return _cm([east, east + Vector2(0, -100)])


## Ağdan kopuk, açık arazide.
static func detached_cm() -> PackedInt64Array:
	return _cm([Vector2(300, 2500), Vector2(300, 2600)])


## Göl üstünden geçen kopuk taslak.
static func lake_cm() -> PackedInt64Array:
	return _cm([Vector2(2700, 250), Vector2(2700, 450)])


static func _cm(points: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for p: Vector2 in points:
		out.append(int(round(p.x * 100.0)))
		out.append(int(round(p.y * 100.0)))
	return out


static func views() -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var next_id := 1
	for code in [CODE_A, CODE_B]:
		for k in PER_REGION:
			var v := ParcelView.new()
			v.id = next_id
			v.region_code = code
			v.center = Vector2(300.0 + 100.0 * k + (0.0 if code == CODE_A else 1800.0), 300.0)
			v.area_m2 = AREA_M2
			v.zone = ZONE
			v.land_value = 1000
			out.append(v)
			next_id += 1
	return out


static func source() -> ListParcelSource:
	return ListParcelSource.create(&"public_works.test_world", views())


## Ekonomi yaması: iki bölge de dar kapasite (varsayılan), periyodik tarama açık; `overrides` bölge kodu -> alanlar.
static func economy_patch(overrides: Dictionary = {}) -> Dictionary:
	var regions := {String(CODE_A): TIGHT.duplicate(), String(CODE_B): TIGHT.duplicate()}
	for code: String in overrides:
		regions[code] = overrides[code]
	return {"regions": {"overrides": regions}}


## Facade + ağ bağlı (yol komutları kayıtlı). `world_seed` farklı tohumlarla çağrılır.
static func setup(world_seed: int = SEED, patch: Dictionary = {}, net: WorldNetwork = null) -> Dictionary:
	var n := net if net != null else network()
	var cfg := EconomyTestSupport.config(patch if not patch.is_empty() else economy_patch())
	var handle := EconomyBootstrap.create(world_seed, source(), cfg)
	assert(handle != null, "EconomyBootstrap.create başarısız")
	var ctx := PublicWorksContext.create(n, RoadDraftRules.new(), PublicWorksConfig.load_default())
	assert(ctx != null, "PublicWorksContext.create başarısız")
	assert(handle.facade.attach_public_works(ctx), "attach_public_works başarısız")
	return {"facade": handle.facade, "net": n, "ctx": ctx, "handle": handle}


static func road(points_cm: PackedInt64Array, road_class: StringName = &"local") -> SimCommand:
	return SimCommand.public_work_road(points_cm, road_class)


## Bölgenin tüm parsellerinin son karar kodları (EconomyState.CODE_NAMES).
static func codes_of(f: SimFacadeImpl, region: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in f.parcel_views(f.parcel_ids(region)):
		out.append(v.decision_code)
	return out


static func decisions_of(f: SimFacadeImpl, region: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for v in f.parcel_views(f.parcel_ids(region)):
		out.append(v.decision)
	return out
