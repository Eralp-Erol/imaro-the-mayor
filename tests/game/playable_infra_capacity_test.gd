extends GdUnitTestSuite
## Yol -> bölge altyapı kapasitesi -> yatırımcı kararı (D-009, D-010; core-loop-v0 §7 "başlangıç boş kapasite
## (yol bölgesi): dar"; ÇALIŞMA MODELİ). Oynanabilir yapılandırma bölge BAŞLANGIÇ boş kapasitesini mutlak birimle
## sınırlar (`playable_economy.json` `infra_free_units_max`): büyük bölgelerde %30 pay (binlerce birim) yolun etkisini
## gizliyordu. Gerçek `PlayableEconomy.config_for` + gerçek yol/imar komutları + gerçek ekonomi; sim kuralları
## DEĞİŞMEZ, yalnız veri.

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const BIG_STOCK_PARCEL := 500
const BIG_UNITS := 4000  # A bölgesinin T0 yükü: %30 pay = 1200 birim (sınırsız eski davranış)
const SMALL_UNITS := 8  # %30 pay = 2 birim: küçük fixture dünyaları
const NO_CAP := {"playable": {"infra_free_units_max": -1}}


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


func _stock(units: int) -> ListStockSource:
	return ListStockSource.create([{"parcel_id": BIG_STOCK_PARCEL, "use": "residential", "units": units, "owner": 1}])


func _cfg(units: int, patch: Dictionary = {}) -> EconomyConfig:
	var base := {"decision": {"unplanned_land_enabled": 1, "priority_review_enabled": 1, "max_reviews_per_tick": 8}}
	var merged: Dictionary = PlayableEconomy._merge(base, patch)
	return PlayableEconomy.config_for(_views(), _stock(units), merged)


func _capacity(cfg: EconomyConfig) -> int:
	return int(cfg.region_params(P.CODE_A)["infra_capacity_units"])


# --- yapılandırma: mutlak birim sınırı ---

func test_playable_data_caps_the_initial_free_capacity_to_a_narrow_absolute_number() -> void:
	var cap := int(JSON.parse_string(FileAccess.get_file_as_string(PlayableEconomy.PATH))["infra_free_units_max"])
	assert_int(cap).override_failure_message("sınır tanımlı ve dar olmalı (yol 100 m = 10 birim)").is_between(0, 10)
	assert_int(_capacity(_cfg(BIG_UNITS))).override_failure_message("büyük bölge: kapasite = yük + sınır + 1") \
		.is_equal(BIG_UNITS + cap + 1)


func test_free_capacity_is_min_of_percent_share_and_absolute_cap() -> void:
	var capped := {"playable": {"infra_free_units_max": 20}}
	assert_int(_capacity(_cfg(BIG_UNITS, capped))).override_failure_message("pay (1200) sınıra (20) iner") \
		.is_equal(BIG_UNITS + 20 + 1)
	assert_int(_capacity(_cfg(SMALL_UNITS, capped))).override_failure_message("pay (2) sınırdan küçükse eski değer") \
		.is_equal(SMALL_UNITS + SMALL_UNITS * 300 / 1000 + 1)


func test_free_capacity_cap_can_be_switched_off_for_control_runs() -> void:
	assert_int(_capacity(_cfg(BIG_UNITS, NO_CAP))).override_failure_message("-1 = eski (sınırsız) davranış") \
		.is_equal(BIG_UNITS + BIG_UNITS * 300 / 1000 + 1)


func test_playable_decision_keeps_the_score_parity_of_a_roomy_region_while_capacity_is_a_pure_gate() -> void:
	var sim_default := EconomyConfig.load_default()
	var cfg := _cfg(BIG_UNITS)
	assert_int(cfg.p("infra_bonus_max")).override_failure_message("oran bonusu kapalı").is_equal(0)
	assert_int(cfg.p("base_threshold") - cfg.p("infra_bonus_max")) \
		.override_failure_message("eşik - azami bonus sim varsayılanıyla aynı kalmalı (boş bölgede skor eskisi gibi)") \
		.is_equal(sim_default.p("base_threshold") - sim_default.p("infra_bonus_max"))


# --- senaryo: yol olmadan plan yetmez, yol varken yatırımcı gelir ---

func _run(cfg: EconomyConfig) -> Dictionary:
	var handle := EconomyBootstrap.create(P.SEED, ListParcelSource.create(&"infra.test_world", _views()), cfg,
			_stock(BIG_UNITS))
	assert_object(handle).is_not_null()
	var ctx := PublicWorksContext.create(P.network(), RoadDraftRules.new(), PublicWorksConfig.load_default())
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	return {"facade": handle.facade}


## Kayıtlı olumsuz kararlarda altyapı etkeni VETO (-1000) olan parsel sayısı.
func _infra_vetoes(f: SimFacadeImpl, ids: Array[int]) -> int:
	var count := 0
	for id in ids:
		for rec in f.reasons_for(SimContract.parcel_ref(id)):
			for factor in rec.factors:
				if factor.name_key == InvestorDecision.F_INFRA and factor.value == InvestorDecision.VETO:
					count += 1
	return count


## Olumlu kararların altyapı etkeninde yazılı kaynak (yol komutu) sayısı.
func _approvals_citing(f: SimFacadeImpl, ids: Array[int], source: StringName) -> int:
	var count := 0
	for id in ids:
		for rec in f.reasons_for(SimContract.parcel_ref(id)):
			for factor in rec.factors:
				if rec.outcome == ReasonRecord.OUTCOME_POSITIVE and factor.name_key == InvestorDecision.F_INFRA \
						and factor.source_ref == source:
					count += 1
	return count


func test_plan_without_road_builds_nothing_because_the_region_is_full() -> void:
	var f := E.f(_run(_cfg(BIG_UNITS)))
	f.advance(20)
	E.plan(f, E.NEAR_A)
	f.advance(80)
	assert_int(E.ticks_of(f, E.KIND_PLAN).size()).override_failure_message("plan yürürlüğe girmeli").is_greater(0)
	assert_int(E.evaluations(f)).override_failure_message("yatırımcı bakmalı (ret kayıtlı)").is_greater(0)
	assert_int(E.approvals(f)).override_failure_message("kapasite yok: yol gelmeden bina olmamalı").is_equal(0)
	assert_int(_infra_vetoes(f, E.NEAR_A)).override_failure_message("SIM-12: ret gerekçesi altyapı olmalı") \
		.is_greater(0)


func test_road_after_plan_adds_capacity_and_the_investor_builds_within_that_capacity() -> void:
	var f := E.f(_run(_cfg(BIG_UNITS)))
	f.advance(20)
	E.plan(f, E.NEAR_A)
	f.advance(40)
	assert_int(E.approvals(f)).is_equal(0)
	var road := E.road_a(f)
	assert_bool(road.is_rejected()).is_false()
	f.advance(80)
	var approvals := E.approvals(f)
	assert_int(approvals).override_failure_message("yol kapasite eklemeli: en az bir bina").is_greater(0)
	# 100 m yol = 10 birim (+1 artık): planlı parsellere yazılan toplam birim bunu aşamaz; 14 parselin hepsi sığmaz.
	var units := 0
	for id in E.NEAR_A:
		units += int(EconomyQuery.parcel_record(f.game_state(), id).get("units", 0))
	assert_int(units).override_failure_message("yolun kapasitesini aşan birim: %d" % units).is_between(2, 11)
	assert_int(approvals).override_failure_message("14 parselin hepsi sığmamalı").is_less(E.NEAR_A.size())
	assert_int(_approvals_citing(f, E.NEAR_A, &"command.%d" % road.command_id)).override_failure_message(
		"SIM-12: onay gerekçesi kapasitenin kaynağı olarak yol komutunu göstermeli").is_equal(approvals)
	assert_int(E.ticks_of(f, E.KIND_STARTED).size()).is_equal(approvals)


func test_road_without_plan_still_builds_nothing() -> void:
	var f := E.f(_run(_cfg(BIG_UNITS)))
	f.advance(20)
	E.road_a(f)
	f.advance(120)
	assert_int(E.approvals(f)).override_failure_message("yalnız yol: bina yok (D-010, CAN-03)").is_equal(0)


func test_uncapped_control_builds_without_the_road_which_is_the_old_hidden_causality() -> void:
	var f := E.f(_run(_cfg(BIG_UNITS, NO_CAP)))
	f.advance(20)
	E.plan(f, E.NEAR_A)
	f.advance(80)
	assert_int(E.approvals(f)).override_failure_message("kontrol: eski %30 payla yol olmadan da bina çıkar") \
		.is_greater(0)
