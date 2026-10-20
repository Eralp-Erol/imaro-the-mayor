class_name EconomyTestSupport
extends RefCounted
## tests/sim/economy ortak yardımcıları (T-013). Test paketi değildir. Koordinat/bölge kodu GÖMÜLMEZ: parseller
## `FacadeTestSupport.fixture_source` ile WorldFixture bölgelerinden (F1/F2) okunur; bölge geçersiz kılmaları fixture
## kodlarını kullanır (gerçek dünya kodlarını değil).

const CONFIG_PATH := "res://data/sim/economy/economy_config.json"
const SEED := 20261020
## Fixture bölgeleri (WorldFixture bilerek D1-D6 değil F1/F2 kullanır).
const R1 := &"F1"
const R2 := &"F2"
const PER_REGION := 6
const USE_RES := 1
const USE_COM := 2


## Ham yapılandırma sözlüğü (JSON, her çağrıda taze).
static func raw_config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))


## Derin birleştirme: `patch` değerleri `base` üzerine yazar (sözlükler özyinelemeli).
static func merge(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: Variant in patch:
		if out.get(key, null) is Dictionary and patch[key] is Dictionary:
			out[key] = merge(out[key], patch[key])
		else:
			out[key] = patch[key]
	return out


static func config(patch: Dictionary = {}) -> EconomyConfig:
	var cfg := EconomyConfig.from_dict(merge(raw_config(), patch))
	assert(cfg.is_valid(), "test yapılandırması geçersiz: %s" % cfg.error)
	return cfg


## Bölge geçersiz kılması yaması: {"regions": {"overrides": {kod: alanlar}}}.
static func regions(overrides: Dictionary) -> Dictionary:
	return {"regions": {"overrides": overrides}}


## Yüksek talep + geniş altyapı (yatırım beklenir) ve düşük talep + dar altyapı (yatırım beklenmez) koşulları.
static func favorable() -> Dictionary:
	return {"initial_households": 400, "infra_capacity_units": 2000}


static func unfavorable() -> Dictionary:
	return {"initial_households": 12, "infra_capacity_units": 4}


## Sentetik parsel kaynağı (ölçek/denge deneyleri): `count` parsel, `region_count` bölgeye bloklar halinde
## bölünür; kodlar T1, T2...
## Konumlar yalnız ızgara düzenidir (dünya verisi değil). Fixture dünyasından bağımsızdır.
static func synthetic_source(count: int, region_count: int = 1, area_m2: int = 1800, land_value: int = 1000,
		zone: StringName = &"zone.residential") -> ListParcelSource:
	var views: Array[ParcelView] = []
	for i in count:
		var v := ParcelView.new()
		v.id = i + 1
		v.region_code = StringName("T%d" % (1 + i * region_count / count))
		v.center = Vector2(float(i % 100) * 40.0, float(i / 100) * 40.0)
		v.area_m2 = area_m2
		v.zone = zone
		v.land_value = land_value
		views.append(v)
	return ListParcelSource.create(&"synthetic.world", views)


## Sentetik kaynaktan ekonomili facade.
static func synthetic_handle(count: int, region_count: int, patch: Dictionary = {},
		world_seed: int = SEED) -> EconomyHandle:
	var h := EconomyBootstrap.create(world_seed, synthetic_source(count, region_count), config(patch))
	assert(h != null, "sentetik EconomyBootstrap.create başarısız")
	return h
