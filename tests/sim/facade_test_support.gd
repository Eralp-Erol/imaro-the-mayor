class_name FacadeTestSupport
extends RefCounted
## tests/sim ortak yardımcıları (T-027): WorldFixture'dan parsel kaynağı ve gerçek SimFacadeImpl kurucuları.
## Test paketi değildir. Koordinat/bölge kodu GÖMÜLMEZ: parseller fixture bölgelerinin ağırlık merkezi etrafından
## okunur (ADR-0005 §7); fixture bilerek F1/F2 kodlarını kullanır.

const SEED := 20261020
## Fixture parsel yerleşimi için bölge merkezinden sapmalar (m); ilk uygun olanlar alınır.
const OFFSETS: Array[Vector2] = [
	Vector2(0, 0), Vector2(300, 0), Vector2(-300, 0), Vector2(0, 300), Vector2(0, -300), Vector2(300, 300),
	Vector2(-300, -300), Vector2(600, 0), Vector2(-600, 0), Vector2(0, 600), Vector2(0, -600),
]
const AREA_M2 := 1800
const LAND_VALUE := 1000
const ZONE := &"zone.residential"


static func fixture_world() -> WorldData:
	return WorldFixture.build()


## Fixture dünyasının her bölgesinde `per_region` parsel; kimlikler 1'den, bölge sırasıyla.
static func fixture_views(world: WorldData, per_region: int = 3) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var next_id := 1
	for region in world.regions:
		var placed := 0
		for offset in OFFSETS:
			var p := region.centroid + offset
			if placed >= per_region:
				break
			if world.is_water(p.x, p.y) or world.region_code_at(p.x, p.y) != region.code:
				continue
			var v := ParcelView.new()
			v.id = next_id
			v.region_code = region.code
			v.center = p
			v.area_m2 = AREA_M2
			v.zone = ZONE
			v.land_value = LAND_VALUE
			out.append(v)
			next_id += 1
			placed += 1
	return out


static func fixture_source(per_region: int = 3) -> ListParcelSource:
	var world := fixture_world()
	return ListParcelSource.create(world.world_id, fixture_views(world, per_region))


static func facade(per_region: int = 3, world_seed: int = SEED) -> SimFacadeImpl:
	var impl := SimFacadeImpl.create(world_seed, fixture_source(per_region))
	assert(impl != null, "SimFacadeImpl.create başarısız")
	return impl
