class_name EconomyWorld
extends RefCounted
## tests/sim/economy facade tabanlı yardımcılar (T-013). Test paketi değildir.

const S := preload("res://tests/sim/economy/economy_test_support.gd")


## Kurulu ekonomili facade; `patch` yapılandırmaya derin birleştirilir.
static func handle(patch: Dictionary = {}, world_seed: int = S.SEED, per_region: int = S.PER_REGION,
		stock: ExistingStockSource = null) -> EconomyHandle:
	var h := EconomyBootstrap.create(world_seed, FacadeTestSupport.fixture_source(per_region), S.config(patch), stock)
	assert(h != null, "EconomyBootstrap.create başarısız")
	return h


static func facade(patch: Dictionary = {}, world_seed: int = S.SEED, per_region: int = S.PER_REGION,
		stock: ExistingStockSource = null) -> SimFacadeImpl:
	return handle(patch, world_seed, per_region, stock).facade


## Facade üzerinden ham ekonomi durumu (salt okunur).
static func data(f: SimFacadeImpl) -> Dictionary:
	return f.game_state().systems.get("economy", {})


static func stage_of(f: SimFacadeImpl, parcel_id: int) -> StringName:
	return f.parcel_views(PackedInt64Array([parcel_id]))[0].development


static func ids(values: Array) -> PackedInt64Array:
	return PackedInt64Array(values)


## Belirli türde olaylar.
static func events(f: SimFacade, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out


## İlk parselin bölge sırasındaki ilk n parsel kimliği: bölge koduna göre.
static func parcels_of(f: SimFacadeImpl, region: StringName) -> PackedInt64Array:
	return f.parcel_ids(region)
