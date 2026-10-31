class_name EconomyPrioritySupport
extends RefCounted
## T-043B test yardımcıları (test paketi değildir): yol + imar sonrası ÖNCELİKLİ değerlendirme kuyruğu. Dünya:
## `PublicWorksSupport` ağı (gerçek yol komutu), parseller yolun yakınına/uzağına elle yerleştirilmiş
## (`ListParcelSource`).
## Koordinat gömülü değildir: konumlar ızgara düğümlerinden (`PublicWorksSupport.GRID_ORIGIN`) türetilir.
##
## Parseller (alan 600 m2 => 3 birim):
##   1..14   Batı (D1) yolun YAKINI: kuzey ayrık yolu (GRID_ORIGIN -> 100 m kuzey) boyunca, yola uzaklık = 10 m x sıra
## (0..130)
##   15..18  Batı (D1) yola UZAK (~900 m)
##   19..20  Doğu (D2), doğu ayrık yolunun yakını
## Altyapı kapasitesi 0: yol gelmeden her yatırım `infrastructure_exhausted` ile reddedilir; 100 m'lik yol bölgeye 10
## birim
## ekler (3 birimlik 3 proje sığar). Yolun ve planın gerçekten etkisi vardır; zorlama yoktur.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const SEEDS: Array[int] = [11, 20261030, 3033, 40404, 505050]
const NEAR_A: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
const FAR_A: Array[int] = [15, 16, 17, 18]
const NEAR_B: Array[int] = [19, 20]
const AREA_M2 := 600
const FILLER_FIRST_ID := 100
const KIND_STARTED := &"event.construction.started"
const KIND_COMPLETED := &"event.construction.completed"
const KIND_ROAD := &"event.road.built"
const KIND_PLAN := &"event.zoning.applied"


## `filler`: yola uzak, plansız boş dolgu parseli sayısı (kimlik FILLER_FIRST_ID'den; yoksa tarama yalnız 20 parseli
## gezer ve
## yolu beklemeden yakalar). Dolgu, oynanabilir dünyadaki gibi periyodik taramanın bütçesini (`max_reviews_per_tick`)
## plansız parsellerle paylaştırır (T-043A notu).
static func views(filler: int = 0) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	for k in filler:
		out.append(_view(FILLER_FIRST_ID + k, P.CODE_A, Vector2(200.0 + 7.0 * k, 2500.0)))
	var origin := P.GRID_ORIGIN
	for k in NEAR_A.size():
		out.append(_view(NEAR_A[k], P.CODE_A, Vector2(origin.x + 10.0 * k, origin.y - 50.0 - 5.0 * (k % 3))))
	for k in FAR_A.size():
		out.append(_view(FAR_A[k], P.CODE_A, Vector2(400.0 + 100.0 * k, 300.0)))
	var east := origin + Vector2(P.DX * P.COLS, 0)
	out.append(_view(NEAR_B[0], P.CODE_B, east + Vector2(50.0, -50.0)))
	out.append(_view(NEAR_B[1], P.CODE_B, east + Vector2(0.0, -20.0)))
	return out


static func _view(id: int, region: StringName, center: Vector2) -> ParcelView:
	var v := ParcelView.new()
	v.id = id
	v.region_code = region
	v.center = center
	v.area_m2 = AREA_M2
	v.zone = &"zone.residential"  # T0 placeholder (plansız modda yok sayılır)
	v.land_value = 1000
	return v


static func source(filler: int = 0) -> ListParcelSource:
	return ListParcelSource.create(&"priority.test_world", views(filler))


## Bayrak + öncelikli kuyruk açık, kapasite 0 (yol olmadan her şey altyapıdan reddedilir). `extra` derin birleşir.
static func patch(extra: Dictionary = {}) -> Dictionary:
	var base := {
		"decision": {"unplanned_land_enabled": 1, "priority_review_enabled": 1, "max_reviews_per_tick": 8},
		"regions": {"overrides": {
			String(P.CODE_A): {"initial_households": 400, "infra_capacity_units": 0},
			String(P.CODE_B): {"initial_households": 400, "infra_capacity_units": 0},
		}},
	}
	return S.merge(base, extra)


## Yol bağlı facade (+ ağ bağlamı). Dönüş: {facade, net, ctx, handle}.
static func setup(extra: Dictionary = {}, world_seed: int = P.SEED, filler: int = 0) -> Dictionary:
	var n := P.network()
	var cfg := S.config(patch(extra))
	var handle := EconomyBootstrap.create(world_seed, source(filler), cfg)
	assert(handle != null, "EconomyBootstrap.create başarısız")
	var ctx := PublicWorksContext.create(n, RoadDraftRules.new(), PublicWorksConfig.load_default())
	assert(ctx != null, "PublicWorksContext.create başarısız")
	assert(handle.facade.attach_public_works(ctx), "attach_public_works başarısız")
	return {"facade": handle.facade, "net": n, "ctx": ctx, "handle": handle}


static func f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


static func plan(facade: SimFacadeImpl, ids: Array[int], zone: StringName = &"zone.mixed") -> CommandResult:
	return facade.submit_command(SimCommand.zoning_propose(PackedInt64Array(ids), zone))


static func road_a(facade: SimFacadeImpl) -> CommandResult:
	return facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local"))


static func road_b(facade: SimFacadeImpl) -> CommandResult:
	return facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local"))


## Ekonomi durumu (doğrudan, salt okunur).
static func eco(facade: SimFacadeImpl) -> Dictionary:
	return facade.game_state().systems.get("economy", {})


## Kuyruk: parsel KİMLİĞİ -> vade günü ({} = kuyruk hiç yaratılmadı). Parsel indeksi = kimlik - 1 (kimlikler 1..n).
static func queue(facade: SimFacadeImpl) -> Dictionary:
	var d := eco(facade)
	var out := {}
	if not d.has("priority"):
		return out
	for i: int in (d["priority"] as Dictionary):
		out[i + 1] = int(d["priority"][i])
	return out


static func queue_commands(facade: SimFacadeImpl) -> Dictionary:
	var d := eco(facade)
	var out := {}
	if not d.has("priority_cmd"):
		return out
	for i: int in (d["priority_cmd"] as Dictionary):
		out[i + 1] = int(d["priority_cmd"][i])
	return out


## Belirli türde olayların tick'leri (artan).
static func ticks_of(facade: SimFacadeImpl, message_key: StringName) -> Array[int]:
	var out: Array[int] = []
	for e in facade.events_since(0):
		if e.message_key == message_key:
			out.append(e.tick)
	return out


static func evaluations(facade: SimFacadeImpl) -> int:
	return int(EconomyQuery.totals(facade.game_state()).get("evaluations", 0))


static func approvals(facade: SimFacadeImpl) -> int:
	return int(EconomyQuery.totals(facade.game_state()).get("approvals", 0))


@warning_ignore("integer_division")
static func median(values: Array[int]) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]  # tek sayıda: ortanca; çiftte üst ortanca
