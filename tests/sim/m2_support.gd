class_name M2Support
extends RefCounted
## T-040 (M2 ilk nedensel döngü) sim tarafı test yardımcıları. Test paketi değildir. Koordinat/bölge kodu GÖMÜLMEZ:
## parseller WorldFixture bölgelerinden (F1/F2) okunur. Senaryolar gerçek `PoliticsBootstrap` (ekonomi + aktör +
## siyaset; oynanabilir sahnedeki kurulumla aynı) ile kurulur; zorlanmış sonuç yoktur: yalnız başlangıç koşulları
## (hane, altyapı kapasitesi) ve oyuncu komutu veridir.

const E := preload("res://tests/sim/economy/economy_test_support.gd")
const SEED := 20261020
## Yalnız oyuncunun imar kararı yatırım değerlendirmesini tetikler (periyodik tarama kapalı): nedensellik yalın.
const ISOLATE := {"decision": {"review_enabled": 0}}
## Yoğun senaryo: F1 dar altyapı + büyük hane, F2 geniş altyapı.
const STRESS := {"F1": {"initial_households": 600, "infra_capacity_units": 140},
	"F2": {"initial_households": 300, "infra_capacity_units": 3000}}


static func politics_handle(economy_patch: Dictionary, per_region: int, world_seed: int = SEED,
		stock: ExistingStockSource = null) -> PoliticsHandle:
	var actors := ActorConfig.load_default()
	var pol := PoliticsConfig.load_default(actors)
	var h := PoliticsBootstrap.create(world_seed, FacadeTestSupport.fixture_source(per_region),
		E.config(economy_patch), stock, actors, pol)
	assert(h != null, "PoliticsBootstrap.create başarısız")
	return h


## Altın senaryo A: yoğun dünya, tüm parseller karma imar önerisi, 120 gün.
static func stress_run(world_seed: int = SEED, days: int = 120) -> SimFacadeImpl:
	var h := politics_handle(E.regions(STRESS), 14, world_seed)
	var r := h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	assert(not r.is_rejected(), "stress komutu reddedildi")
	h.facade.advance(days)
	return h.facade


## Altın senaryo B: AYNI imar komutu, iki koşul (F1 elverişli, F2 elverişsiz), yalnız komut tetikli değerlendirme.
## Dönüş: {facade, approved_parcel, declined_parcel}.
static func two_conditions_run(world_seed: int = SEED, days: int = 60) -> Dictionary:
	var patch := E.merge(ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()}))
	var h := politics_handle(patch, 6, world_seed)
	var f := h.facade
	var p1 := int(f.parcel_ids(E.R1)[0])
	var p2 := int(f.parcel_ids(E.R2)[0])
	var r := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p1, p2]), &"zone.mixed"))
	assert(not r.is_rejected(), "komut reddedildi")
	f.advance(days)
	return {"facade": f, "approved_parcel": p1, "declined_parcel": p2}
