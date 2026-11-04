extends GdUnitTestSuite
## Oynanabilir siyasette altyapı baskısı (D-009, D-010; ÇALIŞMA MODELİ): bölge yük/kapasite oranı ~%99,9'dur (başlangıç
## boş kapasite dar: `playable_economy.json infra_free_units_max`). Sim varsayılan kesim verisi (`blocs.json`) altyapı
## baskısı şikâyetini oran %50'yi geçince başlatır; dolu-ama-sığan bölge oyuncu hiçbir şey yapmadan sürekli
## şikâyet/protesto üretiyordu. Oynanabilir yama baskıyı yalnız GERÇEK aşımda (yük > kapasite) başlatır. Sim varsayılanı
## (GOLDEN A/B) DEĞİŞMEZ. Ölçüm: `tests/sim/perf/infra_politics_probe.gd`;
## rapor `production/log/2026-10-31-altyapi-siyaset-yan-etkisi.md`.

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const BIG_STOCK_PARCEL := 500
const BIG_UNITS := 4000  # D1 T0 yükü (infra_per_unit 1)
const HOUSED := "actor.bloc.1"
const DAYS := 90


func _views() -> Array[ParcelView]:
	var out := E.views()
	var v := ParcelView.new()
	v.id = BIG_STOCK_PARCEL
	v.region_code = P.CODE_A
	v.center = Vector2(100.0, 2000.0)
	v.area_m2 = 1800
	v.zone = &"zone.residential"
	v.land_value = 1000
	out.append(v)
	return out


func _stock() -> ListStockSource:
	return ListStockSource.create([{"parcel_id": BIG_STOCK_PARCEL, "use": "residential", "units": BIG_UNITS, "owner": 1}])


## Oyuncu eylemi YOK; `patch` ekonomi yaması; `politics`: siyaset yapılandırması.
func _run_idle(politics: PoliticsConfig, patch: Dictionary = {}) -> PoliticsHandle:
	var base := {"decision": {"unplanned_land_enabled": 1, "priority_review_enabled": 1, "max_reviews_per_tick": 8}}
	var cfg := PlayableEconomy.config_for(_views(), _stock(), PlayableEconomy._merge(base, patch))
	var h := PoliticsBootstrap.create(P.SEED, ListParcelSource.create(&"infra.pressure_world", _views()), cfg, _stock(),
			null, politics)
	assert_object(h).is_not_null()
	h.facade.advance(DAYS)
	return h


func _grievance(h: PoliticsHandle) -> int:
	return int(PoliticsState.data(h.state())["blocs"][HOUSED]["G"])


## Barınan hane kesiminin (altyapı baskısını duyan) grup tepkisi sayısı; konut arayan kesimin talep tepkisi ayrıdır.
func _housed_reactions(h: PoliticsHandle) -> int:
	var n := 0
	for e in h.facade.events_since(0):
		if e.kind == SimEvent.KIND_GROUP_REACTED and e.subjects.has(HOUSED):
			n += 1
	return n


func _stress_signal(h: PoliticsHandle) -> int:
	return int(PoliticsState.data(h.state())["blocs"][HOUSED]["signals"]["infra_stress"])


func test_full_but_fitting_region_raises_no_infrastructure_grievance_without_player_action() -> void:
	var h := _run_idle(PlayablePolitics.config())
	assert_int(_stress_signal(h)).override_failure_message("kontrol: bölge dolu (oran ~%100) ama aşmıyor") \
		.is_between(990, 1000)
	assert_int(_grievance(h)).override_failure_message("sığan dolu bölge şikâyet üretmemeli").is_equal(0)
	assert_int(_housed_reactions(h)).override_failure_message("oyuncu eylemi yok: barınan kesim tepki vermemeli") \
		.is_equal(0)


func test_control_sim_default_blocs_do_read_the_same_full_region_as_pressure() -> void:
	var h := _run_idle(PoliticsConfig.load_default(ActorConfig.load_default()))
	assert_int(_grievance(h)).override_failure_message("kontrol: sim varsayılanı bu bölgede şikâyet biriktirir") \
		.is_greater(0)
	assert_int(_housed_reactions(h)).override_failure_message("kontrol: ve barınan kesim tepki verir").is_greater(0)


func test_real_overload_still_raises_grievance_on_the_playable_politics() -> void:
	# Kapasite yükün %70'i: oran ~%143 (gerçek aşım, ör. yol geri alındığında).
	var patch := {"regions": {"overrides": {String(P.CODE_A): {"infra_capacity_units": BIG_UNITS * 70 / 100}}}}
	var h := _run_idle(PlayablePolitics.config(), patch)
	assert_int(_stress_signal(h)).is_greater(1000)
	assert_int(_grievance(h)).override_failure_message("gerçek aşım şikâyet üretmeli").is_greater(0)
